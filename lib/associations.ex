defmodule Associations do
  @moduledoc """
  Documentation for `Associations`.
  """

  defmacro __using__(_opts) do
    quote do
      import Associations,
        only: [association: 2, belongs_to: 2, belongs_to: 3, has_many: 2, has_many: 3]

      Module.register_attribute(__MODULE__, :associations, accumulate: true)

      @before_compile Associations
    end
  end

  defmacro __before_compile__(env) do
    for {schema, kind, name, target, opts} <- Module.get_attribute(env.module, :associations) do
      quote do
        def load(%unquote(schema){} = struct, unquote(name)) do
          # kind/target/opts are literals here, resolved at compile time
        end
      end
    end
  end

  @doc """
  Declares the associations of `schema`.
  """
  defmacro association(schema, do: block) do
    quote do
      @association_schema unquote(schema)

      unquote(block)

      Module.delete_attribute(__MODULE__, :association_schema)
    end
  end

  @doc """
  Declares that the enclosing schema holds the foreign key pointing to `schema`.
  """
  defmacro belongs_to(name, schema, opts \\ []) do
    quote do
      @associations {@association_schema, :belongs_to, unquote(name), unquote(schema),
                     unquote(opts)}
    end
  end

  @doc """
  Declares that `schema` holds the foreign key pointing to the enclosing schema.
  """
  defmacro has_many(name, schema, opts \\ []) do
    quote do
      @associations {@association_schema, :has_many, unquote(name), unquote(schema), unquote(opts)}
    end
  end
end
