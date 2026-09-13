defmodule ExampleStore do
  @moduledoc """
  The records the examples in `Associations` and `Garage` are written against.

  `MockStore` is stubbed with this so the doctests read from a fixed store. A test that sets an
  expectation of its own replaces the stub, since `Mox.expect/4` removes it.
  """

  @behaviour Store

  @records %{
    Garage.Car => [
      %Garage.Car{id: 1, color: "red", owner_id: 1, dealer_code: "AAA"},
      %Garage.Car{id: 2, color: "yellow", owner_id: 1, dealer_code: "AAA"},
      %Garage.Car{id: 3, color: "blue", owner_id: 2, dealer_code: "BBB"}
    ],
    Garage.Customer => [
      %Garage.Customer{id: 1, name: "John"},
      %Garage.Customer{id: 2, name: "Jane"}
    ],
    Garage.Dealer => [
      %Garage.Dealer{code: "AAA", name: "Anne"},
      %Garage.Dealer{code: "BBB", name: "Bill"}
    ]
  }

  @impl true
  def list(schema, fields, values) do
    @records
    |> Map.fetch!(schema)
    |> Enum.filter(fn record -> Enum.map(fields, &Map.fetch!(record, &1)) in values end)
  end
end
