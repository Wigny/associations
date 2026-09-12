defmodule Associations.Resolver do
  @moduledoc false

  @typedoc """
  One hop of an association.

  `:target` is the schema to search, `:from` the field the value is read off the record at hand,
  and `:to` the field of `:target` that value is matched against.
  """
  @type step :: %{target: module(), from: atom(), to: atom()}

  @typedoc "A search of one schema by one field and value, such as `%{owner_id: 1}`."
  @type search :: %{atom() => term()}

  @typedoc "A search to run, paired with the schema it searches."
  @type lookup :: {target :: module(), search()}

  @doc """
  Builds the step that reads `from` off a record and searches `target` by `to`.
  """
  @spec step(module(), atom(), atom()) :: step()
  def step(target, from, to), do: %{target: target, from: from, to: to}

  @doc """
  Walks every record through its own steps, searching for all of them at once.

  Each pair given holds the record a walk starts from and the steps of the association being
  loaded for it. The walks advance in lockstep: the steps at the same position all contribute
  their searches to a single batch, which is run before the records it found are walked through
  the next step. Walks may be of different lengths, so records of different schemas, and
  associations of different kinds, resolve in the same batches.

  Records found by the same walk are deduplicated at every hop, so a walk that converges on a
  record through more than one of the records before it holds that record once.

  Returns the records each walk ended on, in the order the walks were given.
  """
  @spec resolve(module(), [{struct(), [step()]}]) :: [[struct()]]
  def resolve(module, walks) do
    hop(module, Enum.map(walks, fn {record, steps} -> {steps, [record]} end))
  end

  defp hop(module, walks) do
    lookups = Enum.map(walks, &pending_lookups/1)

    if Enum.all?(lookups, &Enum.empty?/1) do
      Enum.map(walks, fn {_steps, records} -> records end)
    else
      results = search(module, Enum.concat(lookups))

      hop(module, Enum.zip_with(walks, lookups, &advance(&1, &2, results)))
    end
  end

  defp pending_lookups({[step | _steps], records}), do: Enum.map(records, &lookup(step, &1))
  defp pending_lookups({[], _records}), do: []

  defp lookup(%{target: target, from: from, to: to}, record) do
    {target, %{to => Map.fetch!(record, from)}}
  end

  defp search(module, lookups) do
    lookups
    |> Enum.uniq()
    |> Enum.group_by(fn {target, _search} -> target end, fn {_target, search} -> search end)
    |> Map.new(fn {target, searches} -> {target, module.fetch(target, searches)} end)
  end

  defp advance({[], records}, _lookups, _results), do: {[], records}

  defp advance({[_step | steps], _records}, lookups, results) do
    {steps, lookups |> Enum.flat_map(&read(results, &1)) |> Enum.uniq()}
  end

  defp read(results, {target, search}), do: results |> Map.fetch!(target) |> Map.fetch!(search)
end
