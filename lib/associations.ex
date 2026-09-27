defmodule Associations do
  @moduledoc ~S"""
  Declarative associations between plain structs, loaded in batches.

  The structs stay as they are, with no knowledge of one another. A single module declares how
  they relate and how to list them:

      defmodule Garage do
        use Associations

        alias Garage.{Car, Customer, Dealer, Registration}

        @impl true
        def list(schema, fields, values) do
          Garage.Store.list(schema, fields, values)
        end

        association Car do
          belongs_to :owner, Customer
          belongs_to :dealer, Dealer, foreign_key: :dealer_code, references: :code
          has_one :registration, Registration
        end

        association Customer do
          has_many :cars, Car, foreign_key: :owner_id
        end
      end

  Declaring the associations outside the structs is what lets them be declared for structs you do
  not own, such as the ones an API client or another library hands you, and lets two modules read
  the same structs through association graphs of their own.

  ## Loading

  `use Associations` defines `load/3` and `load_many/3` on the module, and documents them there.
  `load/3` follows an association from a single record, answering with a record for a `belongs_to`
  or a `has_one`, and with a list for a `has_many`:

      iex> Garage.load(%Garage.Car{id: 1, owner_id: 1}, :owner)
      %Garage.Customer{id: 1, name: "John"}

      iex> Garage.load(%Garage.Customer{id: 2, name: "Jane"}, :cars)
      [%Garage.Car{id: 3, color: "blue", owner_id: 2, dealer_code: "BBB"}]

  A `has_many` or a `has_one` declared with `:through` walks other associations, one hop at a time,
  keeping a record only once.

  `load_many/3` follows the same association from many records at once, pairing each of them with
  what it found.
  """

  @doc """
  Lists the records of `schema` whose `fields` hold one of `values`.

  Every association of the module goes through this single callback, so it must handle each schema
  it may be asked for. It is asked for every value at once, so it is meant to be answered with one
  query, one request or one lookup, whatever the records come from.

  `values` holds one row per record being searched for, each row holding a value for every field
  `fields` names, in the same order. Matching the fields in the head fixes the shape of a row, so
  a clause written that way can take it apart directly:

      @impl true
      def list(Car, [:owner_id], values) do
        Store.list_cars(owner_ids: Enum.map(values, fn [owner_id] -> owner_id end))
      end

      def list(Part, [:manufacturer_code, :part_number], values) do
        Catalogue.list_parts(Enum.map(values, fn [code, number] -> {code, number} end))
      end

  A clause that leaves the fields open answers every schema at once, and zips them onto each row
  to say which value belongs to which field:

      @impl true
      def list(schema, fields, values) do
        Store.list_matching(schema, Enum.map(values, &Enum.zip(fields, &1)))
      end

  The records are returned as a flat list, in any order between rows and in the order they are
  wanted within one; `load/3` and `load_many/3` group them by `fields` themselves. A record
  matching none of the rows asked for is ignored, so a source that can only answer more coarsely,
  by each field separately, may return more than it was asked for.

  A batch of searches is grouped by the fields it searches, so loading one association over
  records of different schemas calls this once per set of fields, each call holding every row
  those fields are searched by.

  Those calls run concurrently, each in its own task, so this must be safe to run in parallel and
  the order the calls are made in is not defined. A task does not inherit what the process calling
  `load/3` holds, which matters when the records come from a connection checked out to it: an
  `Ecto.Repo` reads its sandbox connection through `$callers`, which a task does carry, but a
  transaction is bound to the process that opened it, and a call running beside it is outside it.
  Pass `async: false` to `load/3` or `load_many/3` there, and the calls are made in turn, in the
  process asking for them.
  """
  @callback list(schema :: module, fields :: [atom], values :: [[term]]) :: [struct]

  defmacro __using__(_opts) do
    quote generated: true do
      import Associations,
        only: [
          association: 2,
          belongs_to: 2,
          belongs_to: 3,
          has_many: 2,
          has_many: 3,
          has_one: 2,
          has_one: 3
        ]

      @behaviour Associations

      Module.register_attribute(__MODULE__, :declarations, accumulate: true)

      @before_compile Associations

      @doc """
      Loads the association `name` of `record`.

      Returns a single record, or `nil`, for a `belongs_to` or a `has_one`, and a list for a
      `has_many`, including one declared through other associations.

          iex> Garage.load(%Garage.Customer{id: 1}, :dealers)
          [%Garage.Dealer{code: "AAA", name: "Anne"}]

      ## Options

        * `:async` - whether the searches of a single hop are run concurrently, each in its own
          task. Defaults to `true`. Pass `false` where `c:Associations.list/3` has to run in the
          process asking for it, such as inside an `Ecto.Repo` transaction, which is bound to the
          process that opened it and which a task therefore runs outside of.
      """
      @spec load(struct, atom, async: boolean) :: struct | [struct] | nil
      def load(record, name, opts \\ []) do
        Associations.Resolver.load(__MODULE__, record, name, opts)
      end

      @doc """
      Loads the association `name` of every record, searching for all of them at once.

      This is what keeps loading an association over a list from querying once per record. Returns
      a `{record, records}` pair per record, in the order they were given, always with a list on
      the right, whatever the kind of the association.

      The records given may be of different schemas, as long as each of them declares the
      association. Records looking for the same thing are searched for once.

          iex> customer = %Garage.Customer{id: 1, name: "John"}
          iex> dealer = %Garage.Dealer{code: "BBB", name: "Bill"}
          iex> Garage.load_many([customer, dealer], :cars)
          [
            {
              %Garage.Customer{id: 1, name: "John"},
              [
                %Garage.Car{id: 1, color: "red", owner_id: 1, dealer_code: "AAA"},
                %Garage.Car{id: 2, color: "yellow", owner_id: 1, dealer_code: "AAA"}
              ]
            },
            {
              %Garage.Dealer{code: "BBB", name: "Bill"},
              [%Garage.Car{id: 3, color: "blue", owner_id: 2, dealer_code: "BBB"}]
            }
          ]

      Takes the same options as `load/3`.
      """
      @spec load_many([struct], atom, async: boolean) :: [{struct, [struct]}]
      def load_many(records, name, opts \\ []) do
        Associations.Resolver.load_many(__MODULE__, records, name, opts)
      end
    end
  end

  @doc """
  Declares the associations of `schema`.

  The block holds `belongs_to/3`, `has_many/3` and `has_one/3` declarations, all of them read from
  a `schema` struct.

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

  `load/3` reads the foreign key off the struct and searches `schema` by its primary key,
  returning a single record, or `nil` when none matches. It raises when more than one does.

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
    declare(:belongs_to, name, schema, opts)
  end

  @doc """
  Declares that `schema` holds the foreign key pointing to the enclosing schema.

  `load/3` reads the primary key off the struct and searches `schema` by the foreign key,
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

  ## Through other associations

  Given `:through` in place of `schema`, the association walks a list of associations already
  declared, one hop at a time, the way `get_in/2` walks a nested map. Each name is looked up on
  the schema the one before it searched, starting from the enclosing schema, and a name that is
  not declared there fails to compile.

      association Customer do
        has_many :cars, Car, foreign_key: :owner_id
        has_many :dealers, through: [:cars, :dealer]
      end

  Every hop is searched for in its own batch, no matter how many records reached it, and the
  records the last hop found are returned without repeats. The records the hops in between found
  are not returned. The associations gone through must be a `belongs_to`, a `has_many` or a
  `has_one`, not another association declared with `:through`, and `:foreign_key` and
  `:references` do not apply.
  """
  @spec has_many(atom, module, keyword) :: Macro.t()
  defmacro has_many(name, schema, opts \\ []) do
    declare(:has_many, name, schema, opts)
  end

  @doc """
  Declares that `schema` holds the foreign key pointing to the enclosing schema, one record of it.

  Searched for the way `has_many/3` is, taking the same options, but returning a single record, or
  `nil` when none matches. It raises when more than one does.

      association Car do
        has_one :registration, Registration
      end

  See `has_many/3` for the keys and their defaults.

  Takes `:through` as `has_many/3` does, as long as every association it goes through holds a
  single record, and fails to compile otherwise.

      association Service do
        belongs_to :car, Car
        has_one :owner, through: [:car, :owner]
      end
  """
  @spec has_one(atom, module, keyword) :: Macro.t()
  defmacro has_one(name, schema, opts \\ []) do
    declare(:has_one, name, schema, opts)
  end

  defmacro __before_compile__(env) do
    declarations = Module.get_attribute(env.module, :declarations)
    definitions = Associations.Definition.build(declarations)

    quote do
      @doc false
      def __definitions__, do: unquote(Macro.escape(definitions))
    end
  end

  defp declare(kind, name, opts, []) when kind in [:has_many, :has_one] and is_list(opts) do
    {through, opts} = Keyword.pop(opts, :through)

    declare(kind, name, {:through, through}, opts)
  end

  defp declare(kind, name, schema, opts) do
    quote do
      @declarations {@association_schema, unquote(kind), unquote(name), unquote(schema),
                     unquote(opts)}
    end
  end
end
