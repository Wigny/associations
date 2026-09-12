defmodule Garage do
  @moduledoc false

  use Associations

  alias Garage.Car
  alias Garage.Compatibility
  alias Garage.Customer
  alias Garage.Dealer
  alias Garage.Invoice
  alias Garage.Mechanic
  alias Garage.Part
  alias Garage.Service
  alias Garage.Usage

  @impl true
  def fetch(schema, fields, values) do
    Store.list_by(schema, fields, values)
  end

  association Car do
    belongs_to :owner, Customer
    belongs_to :dealer, Dealer, foreign_key: :dealer_code, references: :code
    many_to_many :mechanics, Mechanic, join_through: Service

    many_to_many :compatible_parts, Part,
      join_through: Compatibility,
      join_keys: [
        {:car_id, :id},
        {[:manufacturer_code, :part_number], [:manufacturer_code, :part_number]}
      ]
  end

  association Mechanic do
    many_to_many :cars, Car, join_through: Service
  end

  association Service do
    belongs_to :car, Car
    belongs_to :mechanic, Mechanic
    has_many :usages, Usage
  end

  association Part do
    has_many :usages, Usage,
      foreign_key: [:manufacturer_code, :part_number],
      references: [:manufacturer_code, :part_number]
  end

  association Usage do
    belongs_to :service, Service

    belongs_to :part, Part,
      foreign_key: [:manufacturer_code, :part_number],
      references: [:manufacturer_code, :part_number]
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
