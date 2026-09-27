defmodule Associations.Definition do
  @moduledoc false

  @typedoc """
  An association as `Associations` records it while the module is compiled: the schema it is
  declared on, its kind, its name, the schema it points at, or `{:through, names}`, and its options.
  """
  @type declaration ::
          {schema :: module, kind :: :belongs_to | :has_many | :has_one, name :: atom,
           target :: module | {:through, term}, opts :: keyword}

  @typedoc """
  One hop of an association.

  `:target` is the schema to search, `:from` the fields the values are read off the record at
  hand, `:to` the fields of `:target` those values are matched against, one for one, and `:args`
  what `c:Associations.list/4` is given when searching it, `[]` unless the caller passes any.
  """
  @type step :: %{target: module, from: [atom], to: [atom], args: keyword}

  @typedoc """
  An association as its module declares it.

  `:steps` holds the hops it walks, a single one unless it goes through other associations,
  `:target` the schema the last of them searches, and `:cardinality` whether the association
  holds one record or many.
  """
  @type t :: %{target: module, cardinality: :one | :many, steps: [step, ...]}

  @typedoc """
  Every association of a module, keyed by the schema declaring it and its name.
  """
  @type definitions :: %{optional({module, atom}) => t}

  @doc """
  Builds the definitions of a module out of its `declarations`.

  Associations declared with `:through` are built from the others, so they cannot go through one
  another. Raises `ArgumentError` for a declaration that cannot be resolved.
  """
  @spec build([declaration]) :: definitions
  def build(declarations) do
    {throughs, declarations} =
      Enum.split_with(
        declarations,
        &match?({_schema, _kind, _name, {:through, _hops}, _opts}, &1)
      )

    definitions = Map.new(declarations, &define/1)

    Map.merge(definitions, Map.new(throughs, &define_through(&1, definitions)))
  end

  @doc """
  Fetches the association `name` of `schema` out of `definitions`, raising when it is not there.
  """
  @spec fetch!(definitions, module, atom) :: t
  def fetch!(definitions, schema, name) when is_atom(name) and not is_nil(name) do
    case Map.fetch(definitions, {schema, name}) do
      {:ok, definition} -> definition
      :error -> raise ArgumentError, "#{inspect(schema)} has no #{inspect(name)} association"
    end
  end

  def fetch!(_definitions, _schema, name) do
    raise ArgumentError, "expected an association name, got: #{inspect(name)}"
  end

  defp define({schema, :belongs_to, name, target, opts}) do
    opts = Keyword.validate!(opts, foreign_key: :"#{name}_id", references: :id)

    define(schema, name, target, :one, opts[:foreign_key], opts[:references])
  end

  defp define({schema, kind, name, target, opts}) do
    foreign_key = :"#{schema |> Module.split() |> List.last() |> Macro.underscore()}_id"
    opts = Keyword.validate!(opts, foreign_key: foreign_key, references: :id)

    define(schema, name, target, cardinality(kind), opts[:references], opts[:foreign_key])
  end

  defp define(schema, name, target, cardinality, from, to) do
    from = List.wrap(from)
    to = List.wrap(to)

    if length(from) != length(to) do
      raise ArgumentError,
            "the #{inspect(name)} association of #{inspect(schema)} pairs #{inspect(from)} " <>
              "with #{inspect(to)}, which name a different number of fields"
    end

    step = %{target: target, from: from, to: to, args: []}

    {{schema, name}, %{target: target, cardinality: cardinality, steps: [step]}}
  end

  defp define_through({schema, kind, name, {:through, through}, opts}, definitions) do
    Keyword.validate!(opts, [])

    if not is_list(through) or through == [] do
      raise ArgumentError,
            "the #{inspect(name)} association of #{inspect(schema)} must go through a " <>
              "non-empty list of associations, got: #{inspect(through)}"
    end

    {hops, _schema} =
      Enum.map_reduce(through, schema, fn hop, at ->
        definition = fetch_hop!(definitions, schema, kind, name, at, hop)

        {definition, definition.target}
      end)

    steps = Enum.flat_map(hops, & &1.steps)

    {{schema, name},
     %{target: List.last(hops).target, cardinality: cardinality(kind), steps: steps}}
  end

  defp fetch_hop!(definitions, schema, kind, name, at, hop) do
    case Map.fetch(definitions, {at, hop}) do
      {:ok, %{cardinality: :many}} when kind == :has_one ->
        raise ArgumentError,
              "the #{inspect(name)} association of #{inspect(schema)} is a has_one, so it " <>
                "cannot go through #{inspect(hop)} of #{inspect(at)}, which holds many records"

      {:ok, definition} ->
        definition

      :error ->
        raise ArgumentError,
              "the #{inspect(name)} association of #{inspect(schema)} goes through " <>
                "#{inspect(hop)}, which #{inspect(at)} does not declare as a belongs_to, " <>
                "has_many or has_one"
    end
  end

  defp cardinality(:has_many), do: :many
  defp cardinality(:has_one), do: :one
end
