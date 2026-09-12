defmodule Associations do
  @moduledoc """
  Declarative associations between plain structs.

  A module that `use`s `Associations` implements the `c:fetch/2` callback, which knows how to
  fetch records, and declares one `association/2` block per struct. The declarations are resolved
  while the module compiles, and `load/2` and `load_many/2` read them to search through `c:fetch/2`.

      defmodule Relations do
        use Associations

        @impl true
        def fetch(schema, searches) do
          Map.new(searches, fn search -> {search, Garage.list_by(schema, search)} end)
        end

        association Car do
          belongs_to :owner, Person
        end

        association Person do
          has_many :cars, Car, foreign_key: :owner_id
        end
      end

      Relations.load(person, :cars)
      #=> [%Car{id: 1, owner_id: 1}, %Car{id: 2, owner_id: 1}]

      Relations.load(car, :owner)
      #=> %Person{id: 1}

  A `belongs_to` association returns a single record, or `nil` when none matches. A `has_many`
  association returns a list, and so does a `many_to_many` one, which searches the join schema
  before the associated one.

  `load_many/2` searches for many records at once, which is what keeps loading an association
  over a list from querying once per record. It returns a `{record, records}` pair per record,
  in the order they were given, always with a list on the right.

      Relations.load_many([person, dealer], :cars)
      #=> [{%Person{id: 1}, [%Car{id: 1}, %Car{id: 2}]}, {%Dealer{code: "AAA"}, [%Car{id: 1}]}]

  The records it is given may be of different schemas, as above, as long as each of them declares
  the association.
  """

  alias Associations.Resolver

  @doc """
  Fetches the records of `schema` matching each of `searches`.

  Every association of the module goes through this single callback, so it must handle each schema
  it may be asked for. A search is a map of fields and values, such as `%{owner_id: 1}`, and the
  returned map pairs each of the searches it was given with the records matching it.

      @impl true
      def fetch(schema, searches) do
        Map.new(searches, fn search -> {search, Garage.list_by(schema, search)} end)
      end
  """
  @callback fetch(schema :: module(), searches :: [search]) :: %{search => [struct()]}
            when search: %{atom() => term()}

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

      @doc "Loads the `name` association of `record`."
      @spec load(struct, atom) :: struct | [struct] | nil
      def load(record, name), do: Associations.load(__MODULE__, record, name)

      @doc "Loads the `name` association of every record, searching for all of them at once."
      @spec load_many([struct], atom) :: [{struct, [struct]}]
      def load_many(records, name), do: Associations.load_many(__MODULE__, records, name)
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

    {{schema, name}, %{kind: :belongs_to, steps: [Resolver.step(target, from, to)]}}
  end

  defp define({schema, :has_many, name, target, opts}) do
    from = Keyword.get(opts, :references, :id)
    to = Keyword.get_lazy(opts, :foreign_key, fn -> default_foreign_key(schema) end)

    {{schema, name}, %{kind: :has_many, steps: [Resolver.step(target, from, to)]}}
  end

  defp define({schema, :many_to_many, name, target, opts}) do
    join = Keyword.fetch!(opts, :join_through)

    [{owner_key, owner_reference}, {target_key, target_reference}] =
      Keyword.get_lazy(opts, :join_keys, fn ->
        [{default_foreign_key(schema), :id}, {default_foreign_key(target), :id}]
      end)

    steps = [
      Resolver.step(join, owner_reference, owner_key),
      Resolver.step(target, target_key, target_reference)
    ]

    {{schema, name}, %{kind: :many_to_many, steps: steps}}
  end

  defp default_foreign_key(schema) do
    :"#{schema |> Module.split() |> List.last() |> Macro.underscore()}_id"
  end

  @doc false
  def load(module, %schema{} = record, name) do
    %{kind: kind, steps: steps} = definition!(module, schema, name)
    [results] = Resolver.resolve(module, [{record, steps}])

    case kind do
      :belongs_to -> one!(results, schema, name)
      _kind -> results
    end
  end

  defp one!([], _schema, _name), do: nil
  defp one!([record], _schema, _name), do: record

  defp one!(records, schema, name) do
    raise "the #{inspect(name)} association of #{inspect(schema)} found #{length(records)} records"
  end

  @doc false
  def load_many(module, records, name) when is_list(records) do
    walks =
      Enum.map(records, fn %schema{} = record ->
        %{steps: steps} = definition!(module, schema, name)

        {record, steps}
      end)

    Enum.zip(records, Resolver.resolve(module, walks))
  end

  defp definition!(module, schema, name) do
    case Map.fetch(module.__definitions__(), {schema, name}) do
      {:ok, definition} ->
        definition

      :error ->
        raise ArgumentError, "#{inspect(schema)} has no #{inspect(name)} association"
    end
  end

  @doc """
  Declares the associations of `schema`.

  The block holds `belongs_to/3`, `has_many/3` and `many_to_many/3` declarations, all of them read
  from a `schema` struct.

      association Car do
        belongs_to :owner, Person
      end

  A schema may be declared more than once; the declarations accumulate.
  """
  @spec association(module(), [{:do, Macro.t()}]) :: Macro.t()
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
        belongs_to :owner, Person
        belongs_to :dealer, Dealer, foreign_key: :dealer_code, references: :code
      end

  ## Options

    * `:foreign_key` - the field of the enclosing schema holding the id of the associated record.
      Defaults to `name` suffixed with `_id`, so `belongs_to :owner, Person` reads `:owner_id`.

    * `:references` - the field of `schema` the foreign key points at. Defaults to `:id`.
  """
  @spec belongs_to(atom(), module(), keyword()) :: Macro.t()
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

      association Person do
        has_many :cars, Car, foreign_key: :owner_id
        has_many :licences, Licence
      end

  ## Options

    * `:foreign_key` - the field of `schema` holding the id of the enclosing record. Defaults to
      the enclosing module name, underscored and suffixed with `_id`. Inside `association Person`,
      `has_many :licences, Licence` searches `Licence` by `:person_id`.

    * `:references` - the field of the enclosing schema the foreign key points at. Defaults to
      `:id`.
  """
  @spec has_many(atom(), module(), keyword()) :: Macro.t()
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
      as `join_keys: [car_id: :id, mechanic_id: :id]`.
  """
  @spec many_to_many(atom(), module(), keyword()) :: Macro.t()
  defmacro many_to_many(name, schema, opts) do
    quote do
      @declarations {@association_schema, :many_to_many, unquote(name), unquote(schema),
                     unquote(opts)}
    end
  end
end
