defmodule Associations.Resolver do
  @moduledoc false

  @typedoc """
  One hop of an association.

  `:target` is the schema to search, `:from` the fields the values are read off the record at
  hand, `:to` the fields of `:target` those values are matched against, one for one, and
  `:cardinality` whether the hop holds one record or many.
  """
  @type step :: %{target: module, cardinality: :one | :many, from: [atom], to: [atom]}

  @typedoc """
  A search of one schema by its fields and their values, such as `{Car, [:owner_id], [1]}`.
  """
  @type lookup :: {target :: module, fields :: [atom], values :: [term]}

  @doc """
  Walks every record through `path`, searching for all of them at once.

  Each record is walked through the steps `path` names on its own schema, so records of different
  schemas, and associations of different kinds, resolve in the same batches. The walks advance in
  lockstep: the steps at the same position all contribute their searches, which are grouped by the
  schema and field they search and listed one group at a time, before the records they found are
  walked through the next step.

  The records a walk found are deduplicated at every hop, so a walk that converges on a record
  through more than one of the records before it holds that record once. A record whose key holds
  a `nil` is not searched for at all, since nothing can match it.

  The groups of a single hop are listed concurrently, each in its own task, unless `:async` is
  given as `false`.

  Returns each record paired with the records its walk ended on, in the order they were given.
  """
  @spec load_many(module, [struct], atom | [atom, ...], async: boolean) :: [{struct, [struct]}]
  def load_many(module, records, path, opts) do
    walks =
      Enum.map(records, fn %schema{} = record ->
        {walk!(module, schema, path), [record]}
      end)

    Enum.zip(records, hop(module, walks, opts))
  end

  @doc """
  Shapes the `records` a walk ended on the way `path` answers for `record`.

  A `path` whose steps all hold a single record answers with one record, or `nil` when it found
  none, and raises when it found more than one. One `has_many` anywhere along it answers with the
  records as they are.
  """
  @spec shape(module, struct, atom | [atom, ...], [struct]) :: struct | [struct] | nil
  def shape(module, %schema{}, path, records) do
    if one?(walk!(module, schema, path)) do
      one!(records, schema, path)
    else
      records
    end
  end

  defp walk!(_module, _schema, []) do
    raise ArgumentError, "an association path must hold at least one association"
  end

  defp walk!(module, schema, path) when is_list(path) do
    {steps, _schema} =
      Enum.map_reduce(path, schema, fn name, schema ->
        step = fetch!(module, schema, name)

        {step, step.target}
      end)

    steps
  end

  defp walk!(module, schema, name) when is_atom(name) and not is_nil(name) do
    walk!(module, schema, [name])
  end

  defp walk!(_module, _schema, path) do
    raise ArgumentError, "expected an association path, got: #{inspect(path)}"
  end

  defp fetch!(module, schema, name) do
    case Map.fetch(module.__definitions__(), {schema, name}) do
      {:ok, step} -> step
      :error -> raise ArgumentError, "#{inspect(schema)} has no #{inspect(name)} association"
    end
  end

  defp one?(steps), do: Enum.all?(steps, &(&1.cardinality == :one))

  defp hop(module, walks, opts) do
    if Enum.all?(walks, fn {steps, _records} -> steps == [] end) do
      Enum.map(walks, fn {_steps, records} -> records end)
    else
      lookups = Enum.map(walks, &pending_lookups/1)
      results = search(module, Enum.concat(lookups), opts)

      hop(module, Enum.zip_with(walks, lookups, &advance(&1, &2, results)), opts)
    end
  end

  defp pending_lookups({[step | _steps], records}) do
    records |> Enum.map(&lookup(step, &1)) |> Enum.reject(&unkeyed?/1)
  end

  defp pending_lookups({[], _records}), do: []

  defp lookup(%{target: target, from: from, to: to}, record) do
    {target, to, values(record, from)}
  end

  defp unkeyed?({_target, _fields, values}), do: Enum.any?(values, &is_nil/1)

  defp search(module, lookups, opts) do
    rows = Enum.group_by(lookups, &batch/1, fn {_target, _fields, values} -> values end)
    batches = lookups |> Enum.map(&batch/1) |> Enum.uniq()

    batches
    |> stream(module, rows, opts)
    |> Enum.zip_with(batches, fn result, {_target, fields} = batch ->
      {batch, Enum.group_by(unwrap!(result), &values(&1, fields))}
    end)
    |> Map.new()
  end

  defp stream(batches, module, rows, opts) do
    list = &list(module, &1, Map.fetch!(rows, &1))

    if Keyword.get(opts, :async, true) do
      Task.async_stream(batches, list, timeout: :infinity)
    else
      Enum.map(batches, &{:ok, list.(&1)})
    end
  end

  defp list(module, {target, fields}, rows) do
    {:ok, module.list(target, fields, Enum.uniq(rows))}
  catch
    kind, reason -> {kind, reason, __STACKTRACE__}
  end

  defp unwrap!({:ok, {:ok, records}}), do: records
  defp unwrap!({:ok, {kind, reason, stacktrace}}), do: :erlang.raise(kind, reason, stacktrace)
  defp unwrap!({:exit, reason}), do: exit(reason)

  defp batch({target, fields, _values}), do: {target, fields}

  defp values(record, fields), do: Enum.map(fields, &Map.fetch!(record, &1))

  defp advance({[], records}, _lookups, _results), do: {[], records}

  defp advance({[_step | steps], _records}, lookups, results) do
    {steps, lookups |> Enum.flat_map(&read(results, &1)) |> Enum.uniq()}
  end

  defp read(results, {target, fields, values}) do
    results |> Map.fetch!({target, fields}) |> Map.get(values, [])
  end

  defp one!([], _schema, _path), do: nil
  defp one!([record], _schema, _path), do: record

  defp one!(records, schema, path) do
    raise "the #{inspect(path)} association of #{inspect(schema)} found #{length(records)} records"
  end
end
