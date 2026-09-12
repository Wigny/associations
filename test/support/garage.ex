defmodule Garage do
  @moduledoc false

  @table :fixtures

  def put(records) do
    table = ensure_table_started()

    :ets.insert(table, {:records, records(table) ++ records})
  end

  @doc "Lists the records whose `fields` hold one of `values`, in the order they were put in."
  def list_by(schema, fields, values) do
    table = ensure_table_started()

    record_call(table, {schema, fields, values})

    Enum.filter(records(table), fn record ->
      is_struct(record, schema) and Enum.map(fields, &Map.fetch!(record, &1)) in values
    end)
  end

  @doc "The calls the loader made, in the order it made them."
  def calls do
    @table
    |> :ets.match_object({{:call, :_}, :_})
    |> Enum.sort()
    |> Enum.map(fn {_key, call} -> call end)
  end

  @doc "How many times the loader was called, to tell batched searches from repeated ones."
  def batches, do: length(calls())

  @doc "How many values the loader was asked for, counting a repeated one once."
  def searches do
    Enum.sum_by(calls(), fn {_schema, _field, values} -> length(values) end)
  end

  defp record_call(table, call) do
    index = :ets.update_counter(table, :calls, {2, 1}, {:calls, 0})

    :ets.insert(table, {{:call, index}, call})
  end

  defp records(table) do
    case :ets.lookup(table, :records) do
      [{:records, records}] -> records
      [] -> []
    end
  end

  defp ensure_table_started do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :set, :public])
      table -> table
    end
  end
end
