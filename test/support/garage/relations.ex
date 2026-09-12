defmodule Garage.Relations do
  @moduledoc false

  use Associations

  alias Garage.Car
  alias Garage.Dealer
  alias Garage.Invoice
  alias Garage.Person

  @impl true
  def fetch(schema, searches) do
    Garage.count_batch()

    Map.new(searches, fn search -> {search, Garage.list_by(schema, search)} end)
  end

  association Car do
    belongs_to :owner, Person
    belongs_to :dealer, Dealer, foreign_key: :dealer_code, references: :code
  end

  association Person do
    has_many :cars, Car, foreign_key: :owner_id
  end

  association Person do
    has_many :invoices, Invoice
  end

  association Dealer do
    has_many :cars, Car, foreign_key: :dealer_code, references: :code
  end
end
