defmodule Garage do
  @moduledoc false

  @table :fixtures

  def put(records) do
    :ets.insert(
      ensure_table_started(),
      Enum.map(records, &{{&1.__struct__, :erlang.phash2(&1)}, &1})
    )
  end

  def list_by(schema, search) do
    @table
    |> :ets.match_object({{schema, :_}, search})
    |> Enum.map(fn {_key, record} -> record end)
  end

  @doc "Counts one call of the loader function, to tell batched searches from repeated ones."
  def count_batch do
    :ets.update_counter(ensure_table_started(), :batches, {2, 1}, {:batches, 0})
  end

  def batches do
    case :ets.lookup(@table, :batches) do
      [{:batches, count}] -> count
      [] -> 0
    end
  end

  defp ensure_table_started do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :set, :public])
      table -> table
    end
  end
end
