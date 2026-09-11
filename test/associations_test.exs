defmodule AssociationsTest do
  use ExUnit.Case
  doctest Associations

  defmodule Person do
    defstruct [:id, :name]
  end

  defmodule Car do
    defstruct [:id, :color, :owner_id]
  end

  defmodule MyAssociations do
    use Associations

    association Car do
      belongs_to :owner, Person
    end

    association Person do
      has_many :cars, Car, foreign_key: :onwer_id
    end
  end

  test "TODO" do
    person = %Person{id: 1, name: "John"}
    car1 = %Car{id: 1, color: "red", owner_id: person.id}
    car2 = %Car{id: 2, color: "yellow", owner_id: person.id}
    car3 = %Car{id: 3, color: "blue", owner_id: 2}

    assert_lists MyAssociations.load(person, :cars), [car1, car2]
    assert MyAssociations.load(car2, :person) == person
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
