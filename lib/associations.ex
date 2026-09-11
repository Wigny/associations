defmodule Associations do
  @moduledoc """
  Declarative associations between plain structs.

  A module that `use`s `Associations` declares a `loader/1` function that knows how to fetch
  records and one `association/2` block per struct. From those declarations a `load/2` function
  is generated, with one clause per association.

      defmodule Relations do
        use Associations

        loader fn schema, searches ->
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
  association returns a list.
  """

  @typedoc "The fields a record is searched by, as passed to the loader function."
  @type search :: %{atom() => term()}

  defmacro __using__(_opts) do
    quote do
      import Associations,
        only: [loader: 1, association: 2, belongs_to: 2, belongs_to: 3, has_many: 2, has_many: 3]

      Module.register_attribute(__MODULE__, :associations, accumulate: true)

      @before_compile Associations
    end
  end

  defmacro __before_compile__(env) do
    associations = Module.get_attribute(env.module, :associations)

    [
      for {schema, :belongs_to, name, target, opts} <- associations do
        foreign_key = Keyword.get_lazy(opts, :foreign_key, fn -> :"#{name}_id" end)

        quote do
          def load(%unquote(schema){unquote(foreign_key) => value}, unquote(name)) do
            __dataloader__()
            |> Associations.fetch(unquote(target), %{id: value})
            |> List.first()
          end
        end
      end,
      for {schema, :has_many, name, target, opts} <- associations do
        foreign_key =
          Keyword.get_lazy(opts, :foreign_key, fn ->
            :"#{schema |> Module.split() |> List.last() |> Macro.underscore()}_id"
          end)

        quote do
          def load(%unquote(schema){id: value}, unquote(name)) do
            Associations.fetch(__dataloader__(), unquote(target), %{unquote(foreign_key) => value})
          end
        end
      end
    ]
  end

  @doc false
  @spec fetch(Dataloader.t(), module(), search()) :: term()
  def fetch(dataloader, schema, search) do
    dataloader
    |> Dataloader.load(:loader, schema, search)
    |> Dataloader.run()
    |> Dataloader.get(:loader, schema, search)
  end

  @doc """
  Declares the function used to fetch the associated records.

  `fun` is called with the schema being loaded and the list of searches batched for it, and must
  return a map pairing each of those searches with the records matching it. A search is a map of
  fields and values, such as `%{owner_id: 1}`.

      loader fn schema, searches ->
        Map.new(searches, fn search -> {search, Garage.list_by(schema, search)} end)
      end

  Every association of the module goes through this single function, so it must handle each schema
  it may be asked for.
  """
  @spec loader(Macro.t()) :: Macro.t()
  defmacro loader(fun) do
    quote do
      def __dataloader__ do
        Dataloader.add_source(
          Dataloader.new(),
          :loader,
          Dataloader.KV.new(unquote(fun))
        )
      end
    end
  end

  @doc """
  Declares the associations of `schema`.

  The block holds `belongs_to/3` and `has_many/3` declarations, all of them read from a `schema`
  struct.

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

  `load/2` reads the foreign key off the struct and searches `schema` by `:id`, returning a single
  record or `nil`.

      association Car do
        belongs_to :owner, Person
        belongs_to :dealer, Company, foreign_key: :sold_by_id
      end

  ## Options

    * `:foreign_key` - the field of the enclosing schema holding the id of the associated record.
      Defaults to `name` suffixed with `_id`, so `belongs_to :owner, Person` reads `:owner_id`.
  """
  @spec belongs_to(atom(), module(), keyword()) :: Macro.t()
  defmacro belongs_to(name, schema, opts \\ []) do
    quote do
      @associations {@association_schema, :belongs_to, unquote(name), unquote(schema),
                     unquote(opts)}
    end
  end

  @doc """
  Declares that `schema` holds the foreign key pointing to the enclosing schema.

  `load/2` reads `:id` off the struct and searches `schema` by the foreign key, returning a list
  of records.

      association Person do
        has_many :cars, Car, foreign_key: :owner_id
        has_many :licences, Licence
      end

  ## Options

    * `:foreign_key` - the field of `schema` holding the id of the enclosing record. Defaults to
      the enclosing module name, underscored and suffixed with `_id`. Inside `association Person`,
      `has_many :licences, Licence` searches `Licence` by `:person_id`.
  """
  @spec has_many(atom(), module(), keyword()) :: Macro.t()
  defmacro has_many(name, schema, opts \\ []) do
    quote do
      @associations {@association_schema, :has_many, unquote(name), unquote(schema),
                     unquote(opts)}
    end
  end
end
