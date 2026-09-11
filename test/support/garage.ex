defmodule Garage do
  @moduledoc false

  @table :fixtures

  def put(records) do
    :ets.insert(ensure_table_started(), Enum.map(records, &{{&1.__struct__, &1.id}, &1}))
  end

  def list_by(schema, search) do
    @table
    |> :ets.match_object({{schema, :_}, search})
    |> Enum.map(fn {_key, record} -> record end)
  end

  defp ensure_table_started do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :set, :public])
      table -> table
    end
  end
end
