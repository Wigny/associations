defmodule AssociationsTest do
  use ExUnit.Case
  doctest Associations

  alias Garage.Car
  alias Garage.Person
  alias Garage.Relations

  setup do
    person1 = %Person{id: 1, name: "John"}
    person2 = %Person{id: 2, name: "Mary"}
    car1 = %Car{id: 1, color: "red", owner_id: person1.id}
    car2 = %Car{id: 2, color: "yellow", owner_id: person1.id}
    car3 = %Car{id: 3, color: "blue", owner_id: person2.id}

    Garage.put([person1, person2, car1, car2, car3])

    %{persons: [person1, person2], cars: [car1, car2, car3]}
  end

  test "loads a has_many association", %{persons: [person1, person2], cars: [car1, car2, car3]} do
    assert_lists Relations.load(person1, :cars), [car1, car2]
    assert_lists Relations.load(person2, :cars), [car3]
    assert_lists Relations.load(%Person{id: 3, name: "Ann"}, :cars), []
  end

  test "loads a belongs_to association", %{persons: [person1, person2], cars: [car1, car2, car3]} do
    assert Relations.load(car1, :owner) == person1
    assert Relations.load(car2, :owner) == person1
    assert Relations.load(car3, :owner) == person2
    assert Relations.load(%Car{id: 4, color: "green", owner_id: 3}, :owner) == nil
  end

  defp assert_lists(list1, list2) do
    sorted1 = Enum.sort(list1)
    sorted2 = Enum.sort(list2)

    if sorted1 != sorted2 do
      raise ExUnit.AssertionError,
        left: sorted1,
        right: sorted2,
        message: "Lists do not match",
        expr: nil
    end

    true
  end
end
