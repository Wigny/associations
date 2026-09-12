defmodule Garage.Relations do
  @moduledoc false

  use Associations

  alias Garage.Car
  alias Garage.Customer
  alias Garage.Dealer
  alias Garage.Invoice
  alias Garage.Mechanic
  alias Garage.Service

  @impl true
  def fetch(schema, field, values) do
    Garage.list_by(schema, field, values)
  end

  association Car do
    belongs_to :owner, Customer
    belongs_to :dealer, Dealer, foreign_key: :dealer_code, references: :code
    many_to_many :mechanics, Mechanic, join_through: Service
  end

  association Mechanic do
    many_to_many :cars, Car, join_through: Service
  end

  association Service do
    belongs_to :car, Car
    belongs_to :mechanic, Mechanic
  end

  association Customer do
    has_many :cars, Car, foreign_key: :owner_id
  end

  association Customer do
    has_many :invoices, Invoice
  end

  association Dealer do
    has_many :cars, Car, foreign_key: :dealer_code, references: :code

    many_to_many :customers, Customer,
      join_through: Car,
      join_keys: [dealer_code: :code, owner_id: :id]
  end
end
