defmodule Garage.Relations do
  @moduledoc false

  use Associations

  alias Garage.Car
  alias Garage.Person

  loader fn schema, searches ->
    Map.new(searches, fn search -> {search, Garage.list_by(schema, search)} end)
  end

  association Car do
    belongs_to :owner, Person
  end

  association Person do
    has_many :cars, Car, foreign_key: :owner_id
  end
end
