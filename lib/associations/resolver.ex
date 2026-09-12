defmodule Associations.Resolver do
  @moduledoc false

  @typedoc """
  One hop of an association.

  `:target` is the schema to search, `:from` the fields the values are read off the record at
  hand, and `:to` the fields of `:target` those values are matched against, one for one.
  """
  @type step :: %{target: module(), from: [atom()], to: [atom()]}

  @typedoc """
  A search of one schema by its fields and their values, such as `{Car, [:owner_id], [1]}`.
  """
  @type lookup :: {target :: module(), fields :: [atom()], values :: [term()]}

  @doc """
  Builds the step that reads `from` off a record and searches `target` by `to`.

  Either may name more than one field, and the two are paired in the order they are given.
  """
  @spec step(module(), [atom()], [atom()]) :: step()
  def step(target, from, to), do: %{target: target, from: from, to: to}

  @doc """
  Walks every record through its own steps, searching for all of them at once.

  Each pair given holds the record a walk starts from and the steps of the association being
  loaded for it. The walks advance in lockstep: the steps at the same position all contribute
  their searches, which are grouped by the schema and field they search and fetched one group at
  a time, before the records they found are walked through the next step. Walks may be of
  different lengths, so records of different schemas, and associations of different kinds, resolve
  in the same batches.

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
    {target, to, values(record, from)}
  end

  defp search(module, lookups) do
    batches = Enum.group_by(lookups, &batch/1, fn {_target, _fields, values} -> values end)

    lookups
    |> Enum.map(&batch/1)
    |> Enum.uniq()
    |> Map.new(fn {target, fields} = batch ->
      records = module.fetch(target, fields, batches |> Map.fetch!(batch) |> Enum.uniq())

      {batch, Enum.group_by(records, &values(&1, fields))}
    end)
  end

  defp batch({target, fields, _values}), do: {target, fields}

  defp values(record, fields), do: Enum.map(fields, &Map.fetch!(record, &1))

  defp advance({[], records}, _lookups, _results), do: {[], records}

  defp advance({[_step | steps], _records}, lookups, results) do
    {steps, lookups |> Enum.flat_map(&read(results, &1)) |> Enum.uniq()}
  end

  defp read(results, {target, fields, values}) do
    results |> Map.fetch!({target, fields}) |> Map.get(values, [])
  end
end
