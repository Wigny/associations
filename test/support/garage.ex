defmodule Garage do
  @moduledoc false

  use Associations

  alias Garage.Car
  alias Garage.Compatibility
  alias Garage.Customer
  alias Garage.Dealer
  alias Garage.Invoice
  alias Garage.Part
  alias Garage.Registration
  alias Garage.Service
  alias Garage.Usage

  @impl true
  def list(schema, fields, values, args) do
    MockStore.list(schema, fields, values, args)
  end

  association Car do
    belongs_to :owner, Customer
    belongs_to :dealer, Dealer, foreign_key: :dealer_code, references: :code
    has_one :registration, Registration
    has_many :compatibilities, Compatibility
  end

  association Customer do
    has_many :cars, Car, foreign_key: :owner_id
    has_many :invoices, Invoice
    has_many :dealers, through: [:cars, :dealer]
    has_many :registrations, through: [:cars, :registration]
  end

  association Dealer do
    has_many :cars, Car, foreign_key: :dealer_code, references: :code
    has_many :registrations, through: [:cars, :registration]
  end

  association Registration do
    belongs_to :car, Car
  end

  association Invoice do
    belongs_to :customer, Customer
  end

  association Service do
    belongs_to :car, Car
    has_many :usages, Usage
    has_one :owner, through: [:car, :owner]
  end

  association Part do
    has_many :usages, Usage,
      foreign_key: [:manufacturer_code, :part_number],
      references: [:manufacturer_code, :part_number]

    has_many :compatibilities, Compatibility,
      foreign_key: [:manufacturer_code, :part_number],
      references: [:manufacturer_code, :part_number]
  end

  association Compatibility do
    belongs_to :car, Car

    belongs_to :part, Part,
      foreign_key: [:manufacturer_code, :part_number],
      references: [:manufacturer_code, :part_number]
  end

  association Usage do
    belongs_to :service, Service

    belongs_to :part, Part,
      foreign_key: [:manufacturer_code, :part_number],
      references: [:manufacturer_code, :part_number]
  end
end
