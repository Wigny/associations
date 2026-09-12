defmodule AssociationsTest do
  use ExUnit.Case
  doctest Associations

  alias Garage.Car
  alias Garage.Dealer
  alias Garage.Invoice
  alias Garage.Person
  alias Garage.Relations

  setup do
    person1 = %Person{id: 1, name: "John"}
    person2 = %Person{id: 2, name: "Mary"}
    dealer1 = %Dealer{code: "AAA", name: "Anne"}
    dealer2 = %Dealer{code: "BBB", name: "Bill"}
    car1 = %Car{id: 1, color: "red", owner_id: person1.id, dealer_code: dealer1.code}
    car2 = %Car{id: 2, color: "yellow", owner_id: person1.id, dealer_code: dealer1.code}
    car3 = %Car{id: 3, color: "blue", owner_id: person2.id, dealer_code: dealer2.code}
    invoice1 = %Invoice{id: 1, total: 100, person_id: person1.id}
    invoice2 = %Invoice{id: 2, total: 250, person_id: person1.id}

    Garage.put([person1, person2, dealer1, dealer2, car1, car2, car3, invoice1, invoice2])

    %{
      persons: [person1, person2],
      dealers: [dealer1, dealer2],
      cars: [car1, car2, car3],
      invoices: [invoice1, invoice2]
    }
  end

  test "loads a has_many association", %{persons: [person1, person2], cars: [car1, car2, car3]} do
    assert Relations.load(person1, :cars) == [car1, car2]
    assert Relations.load(person2, :cars) == [car3]
    assert Relations.load(%Person{id: 3, name: "Ann"}, :cars) == []
  end

  test "loads a has_many association through the foreign key derived from the schema", %{
    persons: [person1, person2],
    invoices: [invoice1, invoice2]
  } do
    assert Relations.load(person1, :invoices) == [invoice1, invoice2]
    assert Relations.load(person2, :invoices) == []
  end

  test "loads a belongs_to association", %{persons: [person1, person2], cars: [car1, car2, car3]} do
    assert Relations.load(car1, :owner) == person1
    assert Relations.load(car2, :owner) == person1
    assert Relations.load(car3, :owner) == person2
    assert Relations.load(%Car{id: 4, color: "green", owner_id: 3}, :owner) == nil
  end

  test "loads a has_many association referencing a field other than :id", %{
    dealers: [dealer1, dealer2],
    cars: [car1, car2, car3]
  } do
    assert Relations.load(dealer1, :cars) == [car1, car2]
    assert Relations.load(dealer2, :cars) == [car3]
    assert Relations.load(%Dealer{code: "CCC", name: "Cleo"}, :cars) == []
  end

  test "loads a belongs_to association referencing a field other than :id", %{
    dealers: [dealer1, dealer2],
    cars: [car1, car2, car3]
  } do
    assert Relations.load(car1, :dealer) == dealer1
    assert Relations.load(car2, :dealer) == dealer1
    assert Relations.load(car3, :dealer) == dealer2
    assert Relations.load(%Car{id: 4, dealer_code: "CCC"}, :dealer) == nil
  end

  test "loads a has_many association for many records at once", %{
    persons: [person1, person2],
    cars: [car1, car2, car3]
  } do
    stranger = %Person{id: 3, name: "Ann"}

    assert [{^person1, cars1}, {^person2, cars2}, {^stranger, cars3}] =
             Relations.load_many([person1, person2, stranger], :cars)

    assert cars1 == [car1, car2]
    assert cars2 == [car3]
    assert cars3 == []
  end

  test "loads a belongs_to association for many records at once", %{
    persons: [person1, person2],
    cars: [car1, car2, car3]
  } do
    stray = %Car{id: 4, color: "green", owner_id: 3}

    assert Relations.load_many([car1, car2, car3, stray], :owner) ==
             [{car1, [person1]}, {car2, [person1]}, {car3, [person2]}, {stray, []}]
  end

  test "keeps the order of the records it is given", %{
    persons: [person1, person2],
    cars: [car1, _car2, car3]
  } do
    assert Relations.load_many([car3, car1], :owner) == [{car3, [person2]}, {car1, [person1]}]

    assert [{^person2, [^car3]}, {^person1, _cars}] =
             Relations.load_many([person2, person1], :cars)

    assert Relations.load_many([car1, car1], :owner) == [{car1, [person1]}, {car1, [person1]}]
  end

  test "searches once for records that look for the same thing", %{cars: [car1, car2, _car3]} do
    assert Garage.searches() == 0

    Relations.load_many([car1, car1, car2], :owner)

    assert Garage.searches() == 1
  end

  test "loads the association of records of different schemas at once", %{
    persons: [person1, _person2],
    dealers: [dealer1, _dealer2],
    cars: [car1, car2, _car3]
  } do
    assert Garage.batches() == 0

    assert [{^person1, cars1}, {^dealer1, cars2}] =
             Relations.load_many([person1, dealer1], :cars)

    assert cars1 == [car1, car2]
    assert cars2 == [car1, car2]

    assert Garage.batches() == 1
  end

  test "finds nothing for a record whose key is nil", %{
    persons: [person1, _person2],
    cars: [car1, _car2, _car3]
  } do
    car = %Car{id: 4, color: "green", owner_id: nil}
    person = %Person{id: nil, name: "Nobody"}

    assert Relations.load(car, :owner) == nil
    assert Relations.load(person, :cars) == []
    assert Relations.load_many([car, car1], :owner) == [{car, []}, {car1, [person1]}]
  end

  test "keeps the associations a schema declares in more than one block", %{
    persons: [person1, _person2],
    cars: [car1, car2, _car3],
    invoices: [invoice1, invoice2]
  } do
    assert Relations.load(person1, :cars) == [car1, car2]
    assert Relations.load(person1, :invoices) == [invoice1, invoice2]
  end

  test "raises when a belongs_to association finds more than one record", %{
    persons: [person1, _person2],
    cars: [car1, _car2, _car3]
  } do
    Garage.put([%Person{id: person1.id, name: "John the second"}])

    assert_raise RuntimeError,
                 "the :owner association of Garage.Car found 2 records",
                 fn -> Relations.load(car1, :owner) end
  end

  test "raises for an association the schema does not declare", %{persons: [person1, _person2]} do
    message = "Garage.Person has no :licences association"

    assert_raise ArgumentError, message, fn -> Relations.load(person1, :licences) end
    assert_raise ArgumentError, message, fn -> Relations.load_many([person1], :licences) end
  end

  test "returns no results for no records" do
    assert Relations.load_many([], :cars) == []
  end

  test "searches for every record in a single batch", %{persons: [person1, person2]} do
    assert Garage.batches() == 0

    Relations.load_many([person1, person2], :cars)

    assert Garage.batches() == 1

    Enum.map([person1, person2], &Relations.load(&1, :cars))

    assert Garage.batches() == 3
  end
end
