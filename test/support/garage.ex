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
  alias Garage.Registration
  alias Garage.Service
  alias Garage.Usage

  @impl true
  def fetch(schema, fields, values) do
    MockStore.list(schema, fields, values)
  end

  association Car do
    belongs_to :owner, Customer
    belongs_to :dealer, Dealer, foreign_key: :dealer_code, references: :code
    has_one :registration, Registration
    has_many :services, Service
    has_many :compatibilities, Compatibility
  end

  association Mechanic do
    has_many :services, Service
  end

  association Service do
    belongs_to :car, Car
    belongs_to :mechanic, Mechanic
    has_many :usages, Usage
  end

  association Compatibility do
    belongs_to :part, Part,
      foreign_key: [:manufacturer_code, :part_number],
      references: [:manufacturer_code, :part_number]
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
  end
end
