defmodule Associations.Resolver do
  @moduledoc false

  alias Associations.Definition

  @typedoc """
  A search of one schema by its fields and their values, such as `{{Car, [:owner_id]}, [1]}`.

  Lookups sharing the schema and fields on the left are listed in the same batch.
  """
  @type lookup :: {{target :: module, fields :: [atom]}, values :: [term]}

  @doc """
  Walks `record` through the association `name`, shaped the way `shape/4` shapes it.
  """
  @spec load(module, struct, atom, async: boolean) :: struct | [struct] | nil
  def load(module, record, name, opts) do
    [{^record, records}] = load_many(module, [record], name, opts)

    shape(module, record, name, records)
  end

  @doc """
  Walks every record through the association `name`, searching for all of them at once.

  Each record is walked through the steps `name` declares on its own schema, so records of
  different schemas, and associations of different kinds, resolve in the same batches. The walks
  advance in lockstep: at every hop, the lookups of all of them are grouped by the schema and
  fields they search, each group is listed with `c:Associations.list/3`, and the records found are
  matched back to the rows by those fields before the next hop.

  The records a walk found are deduplicated at every hop, so a walk that converges on a record
  through more than one of the records before it holds that record once. A record whose key holds
  a `nil` is not searched for at all, since nothing can match it.

  The groups of a single hop are listed concurrently, each in its own task, unless `:async` is
  given as `false`.

  Returns each record paired with the records its walk ended on, in the order they were given.
  """
  @spec load_many(module, [struct], atom, async: boolean) :: [{struct, [struct]}]
  def load_many(module, records, name, opts) when is_list(records) do
    definitions = module.__definitions__()

    walks =
      Enum.map(records, fn %schema{} = record ->
        {Definition.fetch!(definitions, schema, name).steps, [record]}
      end)

    Enum.zip(records, walk(walks, &list_all(module, &1, opts)))
  end

  @doc """
  Shapes the `records` a walk ended on the way the association `name` answers for `record`.

  An association holding a single record answers with one record, or `nil` when it found none,
  and raises when it found more than one. An association holding many answers with the records
  as they are.
  """
  @spec shape(module, struct, atom, [struct]) :: struct | [struct] | nil
  def shape(module, %schema{}, name, records) do
    definition = Definition.fetch!(module.__definitions__(), schema, name)

    if definition.cardinality == :one do
      one!(records, schema, name)
    else
      records
    end
  end

  defp walk(walks, list) do
    if Enum.all?(walks, fn {steps, _records} -> steps == [] end) do
      Enum.map(walks, fn {_steps, records} -> records end)
    else
      lookups = Enum.map(walks, &pending_lookups/1)

      rows = Enum.group_by(Enum.concat(lookups), &elem(&1, 0), &elem(&1, 1))

      found =
        for {{_target, fields} = batch, records} <- list.(rows), record <- records do
          {{batch, values(record, fields)}, record}
        end

      results = Enum.group_by(found, &elem(&1, 0), &elem(&1, 1))

      walk(Enum.zip_with(walks, lookups, &advance(&1, &2, results)), list)
    end
  end

  defp pending_lookups({[%{target: target, from: from, to: to} | _steps], records}) do
    lookups = Enum.map(records, &{{target, to}, values(&1, from)})

    Enum.reject(lookups, fn {_batch, values} -> Enum.any?(values, &is_nil/1) end)
  end

  defp pending_lookups({[], _records}), do: []

  defp list_all(module, rows, opts) do
    if Keyword.get(opts, :async, true) do
      tasks = Task.async_stream(rows, &list_safely(module, &1), timeout: :infinity)

      Map.new(tasks, &unwrap!/1)
    else
      Map.new(rows, &list(module, &1))
    end
  end

  defp list(module, {{target, fields} = batch, rows}) do
    {batch, module.list(target, fields, Enum.uniq(rows))}
  end

  defp list_safely(module, rows) do
    {:ok, list(module, rows)}
  catch
    kind, reason -> {kind, reason, __STACKTRACE__}
  end

  defp unwrap!({:ok, {:ok, result}}), do: result
  defp unwrap!({:ok, {kind, reason, stacktrace}}), do: :erlang.raise(kind, reason, stacktrace)
  defp unwrap!({:exit, reason}), do: exit(reason)

  defp values(record, fields), do: Enum.map(fields, &Map.fetch!(record, &1))

  defp advance({[], records}, _lookups, _results), do: {[], records}

  defp advance({[_step | steps], _records}, lookups, results) do
    found = Enum.flat_map(lookups, &Map.get(results, &1, []))

    {steps, Enum.uniq(found)}
  end

  defp one!([], _schema, _name), do: nil
  defp one!([record], _schema, _name), do: record

  defp one!(records, schema, name) do
    raise "the #{inspect(name)} association of #{inspect(schema)} found #{length(records)} records"
  end
end
