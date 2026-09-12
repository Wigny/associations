defmodule Garage do
  @moduledoc false

  @table :fixtures

  def put(records) do
    table = ensure_table_started()

    # Indexed from the rows already there, so a later put does not reuse a key, and so that the
    # records are listed in the order they were put in.
    rows =
      records
      |> Enum.with_index(:ets.info(table, :size))
      |> Enum.map(fn {record, index} -> {{record.__struct__, index}, record} end)

    :ets.insert(table, rows)
  end

  @doc "Lists the records matching `search`, in the order they were put in."
  def list_by(schema, search) do
    count(:searches)

    @table
    |> :ets.match_object({{schema, :_}, search})
    |> Enum.sort()
    |> Enum.map(fn {_key, record} -> record end)
  end

  @doc "Counts one call of the loader function, to tell batched searches from repeated ones."
  def count_batch, do: count(:batches)

  def batches, do: counter(:batches)

  @doc "How many searches the loader was asked for, counting a repeated one once."
  def searches, do: counter(:searches)

  defp count(name) do
    :ets.update_counter(ensure_table_started(), name, {2, 1}, {name, 0})
  end

  defp counter(name) do
    case :ets.lookup(@table, name) do
      [{^name, count}] -> count
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
