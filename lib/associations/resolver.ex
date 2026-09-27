defmodule Associations.Resolver do
  @moduledoc false

  alias Associations.Definition

  @typedoc """
  A search of one schema by its fields and their values, such as
  `{{Car, [:owner_id], [], nil}, [1]}`.

  Lookups sharing the batch on the left are listed in the same call. Besides the schema and the
  fields, it holds the args the call is given and, when there are any, every row the walk making
  the lookup searches, so that a call given args lists the rows of walks ending on the same rows
  only.
  """
  @type lookup ::
          {{target :: module, fields :: [atom], args :: keyword, partition :: [[term]] | nil},
           values :: [term]}

  @doc """
  Walks `record` through the association `name`, shaped the way `shape/4` shapes it.
  """
  @spec load(module, struct, atom, async: boolean, args: keyword) :: struct | [struct] | nil
  def load(module, record, name, opts) do
    [{^record, records}] = load_many(module, [record], name, opts)

    shape(module, record, name, records)
  end

  @doc """
  Walks every record through the association `name`, searching for all of them at once.

  Each record is walked through the steps `name` declares on its own schema, so records of
  different schemas, and associations of different kinds, resolve in the same batches. The walks
  advance in lockstep: at every hop, the lookups of all of them are grouped by the schema and
  fields they search, each group is listed with `c:Associations.list/4`, and the records found are
  matched back to the rows by those fields before the next hop.

  Given `:args`, the last hop is not batched across records: each record's walk lists the rows it
  reached in one call of its own, with the args, so the args shape everything that record ends on.
  Walks ending on the same rows share a call. The hops before the last are batched as usual,
  without the args.

  The records a walk found keep the order the call listing them returned them in, and are
  deduplicated at every hop, so a walk that converges on a record through more than one of the
  records before it holds that record once. A record whose key holds
  a `nil` is not searched for at all, since nothing can match it.

  The groups of a single hop are listed concurrently, each in its own task, unless `:async` is
  given as `false`.

  Returns each record paired with the records its walk ended on, in the order they were given.
  """
  @spec load_many(module, [struct], atom, async: boolean, args: keyword) :: [{struct, [struct]}]
  def load_many(module, records, name, opts) when is_list(records) do
    definitions = module.__definitions__()
    args = Keyword.get(opts, :args, [])

    walks =
      Enum.map(records, fn %schema{} = record ->
        steps = Definition.fetch!(definitions, schema, name).steps

        {List.update_at(steps, -1, &%{&1 | args: args}), [record]}
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
        for {{_target, fields, _args, _partition} = batch, records} <- list.(rows),
            {record, position} <- Enum.with_index(records) do
          {{batch, values(record, fields)}, {position, record}}
        end

      results = Enum.group_by(found, &elem(&1, 0), &elem(&1, 1))

      walk(Enum.zip_with(walks, lookups, &advance(&1, &2, results)), list)
    end
  end

  defp pending_lookups({[%{target: target, from: from, to: to, args: args} | _steps], records}) do
    rows = Enum.map(records, &values(&1, from))
    rows = Enum.reject(rows, fn values -> Enum.any?(values, &is_nil/1) end)
    partition = if args != [], do: rows |> Enum.uniq() |> Enum.sort()

    Enum.map(rows, &{{target, to, args, partition}, &1})
  end

  defp pending_lookups({[], _records}), do: []

  defp list_all(module, rows, opts) do
    if Keyword.get(opts, :async, true) do
      tasks = Task.async_stream(rows, &list_safely(module, &1), timeout: :infinity)

      Enum.map(tasks, &unwrap!/1)
    else
      Enum.map(rows, &list(module, &1))
    end
  end

  defp list(module, {{target, fields, args, _partition} = batch, rows}) do
    {batch, module.list(target, fields, Enum.uniq(rows), args)}
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

    {steps, found |> List.keysort(0) |> Enum.map(&elem(&1, 1)) |> Enum.uniq()}
  end

  defp one!([], _schema, _name), do: nil
  defp one!([record], _schema, _name), do: record

  defp one!(records, schema, name) do
    raise "the #{inspect(name)} association of #{inspect(schema)} found #{length(records)} records"
  end
end
