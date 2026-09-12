defmodule Associations do
  @moduledoc """
  Declarative associations between plain structs.

  A module that `use`s `Associations` implements the `c:fetch/3` callback, which knows how to
  fetch records, and declares one `association/2` block per struct. The declarations are resolved
  while the module compiles, and `load/2` and `load_many/2` read them to search through `c:fetch/3`.

      defmodule Garage do
        use Associations

        @impl true
        def fetch(schema, fields, values) do
          Store.list_by(schema, fields, values)
        end

        association Car do
          belongs_to :owner, Customer
        end

        association Customer do
          has_many :cars, Car, foreign_key: :owner_id
        end
      end

      Garage.load(customer, :cars)
      #=> [%Car{id: 1, owner_id: 1}, %Car{id: 2, owner_id: 1}]

      Garage.load(car, :owner)
      #=> %Customer{id: 1}

  A `belongs_to` association returns a single record, or `nil` when none matches; it raises when
  more than one does. A `has_many` association returns a list, and so does a `many_to_many` one,
  which searches the join schema before the associated one.

  `load_many/2` searches for many records at once, which is what keeps loading an association
  over a list from querying once per record. It returns a `{record, records}` pair per record,
  in the order they were given, always with a list on the right.

      Garage.load_many([customer, dealer], :cars)
      #=> [{%Customer{id: 1}, [%Car{id: 1}, %Car{id: 2}]}, {%Dealer{code: "AAA"}, [%Car{id: 1}]}]

  The records it is given may be of different schemas, as above, as long as each of them declares
  the association. Records looking for the same thing are searched for once.

  Both functions take a path of associations as well as a single one, walking one association of
  the records the one before it found, the way `get_in/2` walks a nested map. Every hop is
  searched for in its own batch, no matter how many records reached it, and the records the last
  hop found are returned without repeats.

      Garage.load(customer, [:cars, :dealer])
      #=> [%Dealer{code: "AAA"}]

  A path returns a single record only when every association along it is a `belongs_to`; one
  `has_many` or `many_to_many` anywhere in it makes the result a list. The records the hops in
  between found are not returned, so a path tells you which records it ended on, not which of the
  records before them led there.
  """

  alias Associations.Resolver

  @doc """
  Fetches the records of `schema` whose `fields` hold one of `values`.

  Every association of the module goes through this single callback, so it must handle each schema
  it may be asked for. It is asked for every value at once, so it is meant to be answered with one
  query, one request or one lookup, whatever the records come from.

  `values` holds one row per record being searched for, each row holding a value for every field
  `fields` names, in the same order. Matching the fields in the head fixes the shape of a row, so
  a clause written that way can take it apart directly:

      @impl true
      def fetch(Car, [:owner_id], values) do
        Store.list_cars(owner_ids: Enum.map(values, fn [owner_id] -> owner_id end))
      end

      def fetch(Part, [:manufacturer_code, :part_number], values) do
        Catalogue.list_parts(Enum.map(values, fn [code, number] -> {code, number} end))
      end

  A clause that leaves the fields open answers every schema at once, and zips them onto each row
  to say which value belongs to which field:

      @impl true
      def fetch(schema, fields, values) do
        Store.list_matching(schema, Enum.map(values, &Enum.zip(fields, &1)))
      end

  The records are returned as a flat list, in any order between rows and in the order they are
  wanted within one; `load/2` and `load_many/2` group them by `fields` themselves. A record
  matching none of the rows asked for is ignored, so a source that can only answer more coarsely,
  by each field separately, may return more than it was asked for.

  A batch of searches is grouped by the fields it searches, so loading one association over
  records of different schemas calls this once per set of fields, each call holding every row
  those fields are searched by.

  Those calls run concurrently, each in its own task, so this must be safe to run in parallel and
  the order the calls are made in is not defined. A task does not inherit what the process calling
  `load/2` holds, which matters when the records come from a connection checked out to it: an
  `Ecto.Repo` reads its sandbox connection through `$callers`, which a task does carry, but a
  transaction is bound to the process that opened it, and a fetch running beside it is outside it.
  Pass `async: false` to `load/3` or `load_many/3` there, and the calls are made in turn, in the
  process asking for them.
  """
  @callback fetch(schema :: module, fields :: [atom], values :: [[term]]) :: [struct]

  defmacro __using__(_opts) do
    quote do
      import Associations,
        only: [
          association: 2,
          belongs_to: 2,
          belongs_to: 3,
          has_many: 2,
          has_many: 3,
          many_to_many: 3
        ]

      @behaviour Associations

      Module.register_attribute(__MODULE__, :declarations, accumulate: true)

      @before_compile Associations

      @doc """
      Loads the association `path` of `record`, either one name or a list of them.

      ## Options

        * `:async` - whether the searches of a single hop are run concurrently, each in its own
          task. Defaults to `true`. Pass `false` where `c:Associations.fetch/3` has to run in the
          process asking for it, such as inside an `Ecto.Repo` transaction, which is bound to the
          process that opened it and which a task therefore runs outside of.
      """
      @spec load(struct, atom | [atom], async: boolean) :: struct | [struct] | nil
      def load(record, path, opts \\ []) do
        Associations.load(__MODULE__, record, path, opts)
      end

      @doc """
      Loads the association `path` of every record, searching for all of them at once.

      Takes the same options as `load/3`.
      """
      @spec load_many([struct], atom | [atom], async: boolean) :: [{struct, [struct]}]
      def load_many(records, path, opts \\ []) do
        Associations.load_many(__MODULE__, records, path, opts)
      end
    end
  end

  @doc """
  Declares the associations of `schema`.

  The block holds `belongs_to/3`, `has_many/3` and `many_to_many/3` declarations, all of them read
  from a `schema` struct.

      association Car do
        belongs_to :owner, Customer
      end

  A schema may be declared more than once; the declarations accumulate.
  """
  @spec association(module, [{:do, Macro.t()}]) :: Macro.t()
  defmacro association(schema, do: block) do
    quote do
      @association_schema unquote(schema)

      unquote(block)

      Module.delete_attribute(__MODULE__, :association_schema)
    end
  end

  @doc """
  Declares that the enclosing schema holds the foreign key pointing to `schema`.

  `load/2` reads the foreign key off the struct and searches `schema` by its primary key,
  returning a single record or `nil`.

      association Car do
        belongs_to :owner, Customer
        belongs_to :dealer, Dealer, foreign_key: :dealer_code, references: :code
      end

  ## Options

    * `:foreign_key` - the field of the enclosing schema holding the id of the associated record.
      Defaults to `name` suffixed with `_id`, so `belongs_to :owner, Customer` reads `:owner_id`.

    * `:references` - the field of `schema` the foreign key points at. Defaults to `:id`.

  Both take a list of fields as well as a single one, for a `schema` identified by more than one,
  and are then paired in the order they are given.

      association Usage do
        belongs_to :part, Part,
          foreign_key: [:manufacturer_code, :part_number],
          references: [:manufacturer_code, :part_number]
      end
  """
  @spec belongs_to(atom, module, keyword) :: Macro.t()
  defmacro belongs_to(name, schema, opts \\ []) do
    quote do
      @declarations {@association_schema, :belongs_to, unquote(name), unquote(schema),
                     unquote(opts)}
    end
  end

  @doc """
  Declares that `schema` holds the foreign key pointing to the enclosing schema.

  `load/2` reads the primary key off the struct and searches `schema` by the foreign key,
  returning a list of records.

      association Customer do
        has_many :cars, Car, foreign_key: :owner_id
        has_many :invoices, Invoice
      end

  ## Options

    * `:foreign_key` - the field of `schema` holding the id of the enclosing record. Defaults to
      the enclosing module name, underscored and suffixed with `_id`. Inside `association Customer`,
      `has_many :invoices, Invoice` searches `Invoice` by `:customer_id`.

    * `:references` - the field of the enclosing schema the foreign key points at. Defaults to
      `:id`.

  Both take a list of fields as well as a single one, for an enclosing schema identified by more
  than one, and are then paired in the order they are given.

      association Part do
        has_many :usages, Usage,
          foreign_key: [:manufacturer_code, :part_number],
          references: [:manufacturer_code, :part_number]
      end
  """
  @spec has_many(atom, module, keyword) :: Macro.t()
  defmacro has_many(name, schema, opts \\ []) do
    quote do
      @declarations {@association_schema, :has_many, unquote(name), unquote(schema),
                     unquote(opts)}
    end
  end

  @doc """
  Declares that the enclosing schema and `schema` point at each other through a join schema.

  `load/2` reads the primary key off the struct and searches the join schema by the foreign key
  pointing at it, then searches `schema` for the records those join records point at, returning a
  list. The two searches are two separate batches.

      association Car do
        many_to_many :mechanics, Mechanic, join_through: Service
      end

  ## Options

    * `:join_through` - the schema holding the foreign keys of both sides. Required.

    * `:join_keys` - the two pairs of fields the join schema is searched by, each pairing a field
      of the join schema with the field it points at. Defaults to the module name of each side,
      underscored and suffixed with `_id`, pointing at `:id`, so the declaration above is the same
      as `join_keys: [car_id: :id, mechanic_id: :id]`. Either side of a pair takes a list of
      fields as well as a single one, for a schema identified by more than one.

      The first pair is always the one pointing at the enclosing schema, so a composite side
      cannot be written with the keyword syntax unless it is the second.

          association Car do
            many_to_many :compatible_parts, Part,
              join_through: Compatibility,
              join_keys: [
                {:car_id, :id},
                {[:manufacturer_code, :part_number], [:manufacturer_code, :part_number]}
              ]
          end
  """
  @spec many_to_many(atom, module, keyword) :: Macro.t()
  defmacro many_to_many(name, schema, opts) do
    quote do
      @declarations {@association_schema, :many_to_many, unquote(name), unquote(schema),
                     unquote(opts)}
    end
  end

  defmacro __before_compile__(env) do
    declarations = Module.get_attribute(env.module, :declarations)
    definitions = Map.new(declarations, &define/1)

    quote do
      @doc false
      def __definitions__, do: unquote(Macro.escape(definitions))
    end
  end

  defp define({schema, :belongs_to, name, target, opts}) do
    from = Keyword.get_lazy(opts, :foreign_key, fn -> :"#{name}_id" end)
    to = Keyword.get(opts, :references, :id)

    {{schema, name}, %{kind: :belongs_to, steps: [step!(schema, name, target, from, to)]}}
  end

  defp define({schema, :has_many, name, target, opts}) do
    from = Keyword.get(opts, :references, :id)
    to = Keyword.get_lazy(opts, :foreign_key, fn -> default_foreign_key(schema) end)

    {{schema, name}, %{kind: :has_many, steps: [step!(schema, name, target, from, to)]}}
  end

  defp define({schema, :many_to_many, name, target, opts}) do
    join = Keyword.fetch!(opts, :join_through)

    [{owner_key, owner_reference}, {target_key, target_reference}] =
      Keyword.get_lazy(opts, :join_keys, fn ->
        [{default_foreign_key(schema), :id}, {default_foreign_key(target), :id}]
      end)

    steps = [
      step!(schema, name, join, owner_reference, owner_key),
      step!(schema, name, target, target_key, target_reference)
    ]

    {{schema, name}, %{kind: :many_to_many, steps: steps}}
  end

  defp step!(schema, name, target, from, to) do
    from = List.wrap(from)
    to = List.wrap(to)

    if length(from) != length(to) do
      raise ArgumentError,
            "the #{inspect(name)} association of #{inspect(schema)} pairs #{inspect(from)} " <>
              "with #{inspect(to)}, which name a different number of fields"
    end

    Resolver.step(target, from, to)
  end

  defp default_foreign_key(schema) do
    :"#{schema |> Module.split() |> List.last() |> Macro.underscore()}_id"
  end

  @doc false
  def load(module, %schema{} = record, path, opts) do
    {kinds, steps} = walk!(module, schema, path)
    [results] = Resolver.resolve(module, [{record, steps}], opts)

    if Enum.all?(kinds, &(&1 == :belongs_to)) do
      one!(results, schema, path)
    else
      results
    end
  end

  @doc false
  def load_many(module, records, path, opts) when is_list(records) do
    walks =
      Enum.map(records, fn %schema{} = record ->
        {_kinds, steps} = walk!(module, schema, path)

        {record, steps}
      end)

    Enum.zip(records, Resolver.resolve(module, walks, opts))
  end

  defp walk!(_module, _schema, []) do
    raise ArgumentError, "an association path must hold at least one association"
  end

  defp walk!(module, schema, path) when is_list(path) do
    {kinds, steps, _schema} =
      Enum.reduce(path, {[], [], schema}, fn name, {kinds, steps, schema} ->
        %{kind: kind, steps: hops} = definition!(module, schema, name)
        %{target: target} = List.last(hops)

        {[kind | kinds], steps ++ hops, target}
      end)

    {kinds, steps}
  end

  defp walk!(module, schema, name), do: walk!(module, schema, [name])

  defp definition!(module, schema, name) do
    case Map.fetch(module.__definitions__(), {schema, name}) do
      {:ok, definition} ->
        definition

      :error ->
        raise ArgumentError, "#{inspect(schema)} has no #{inspect(name)} association"
    end
  end

  defp one!([], _schema, _path), do: nil
  defp one!([record], _schema, _path), do: record

  defp one!(records, schema, path) do
    raise "the #{inspect(path)} association of #{inspect(schema)} found #{length(records)} records"
  end
end
