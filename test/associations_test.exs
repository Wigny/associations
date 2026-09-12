defmodule AssociationsTest do
  use ExUnit.Case
  doctest Associations

  alias Garage.Car
  alias Garage.Customer
  alias Garage.Dealer
  alias Garage.Invoice
  alias Garage.Mechanic
  alias Garage.Relations
  alias Garage.Service

  setup do
    customer1 = %Customer{id: 1, name: "John"}
    customer2 = %Customer{id: 2, name: "Mary"}
    dealer1 = %Dealer{code: "AAA", name: "Anne"}
    dealer2 = %Dealer{code: "BBB", name: "Bill"}
    car1 = %Car{id: 1, color: "red", owner_id: customer1.id, dealer_code: dealer1.code}
    car2 = %Car{id: 2, color: "yellow", owner_id: customer1.id, dealer_code: dealer1.code}
    car3 = %Car{id: 3, color: "blue", owner_id: customer2.id, dealer_code: dealer2.code}
    invoice1 = %Invoice{id: 1, total: 100, customer_id: customer1.id}
    invoice2 = %Invoice{id: 2, total: 250, customer_id: customer1.id}
    mechanic1 = %Mechanic{id: 1, name: "Sam"}
    mechanic2 = %Mechanic{id: 2, name: "Rita"}
    service1 = %Service{id: 1, cost: 80, car_id: car1.id, mechanic_id: mechanic1.id}
    service2 = %Service{id: 2, cost: 40, car_id: car1.id, mechanic_id: mechanic2.id}
    service3 = %Service{id: 3, cost: 60, car_id: car2.id, mechanic_id: mechanic1.id}

    Garage.put([
      customer1,
      customer2,
      dealer1,
      dealer2,
      car1,
      car2,
      car3,
      invoice1,
      invoice2,
      mechanic1,
      mechanic2,
      service1,
      service2,
      service3
    ])

    %{
      customers: [customer1, customer2],
      dealers: [dealer1, dealer2],
      cars: [car1, car2, car3],
      invoices: [invoice1, invoice2],
      mechanics: [mechanic1, mechanic2]
    }
  end

  test "loads a has_many association", %{
    customers: [customer1, customer2],
    cars: [car1, car2, car3]
  } do
    assert Relations.load(customer1, :cars) == [car1, car2]
    assert Relations.load(customer2, :cars) == [car3]
    assert Relations.load(%Customer{id: 3, name: "Ann"}, :cars) == []
  end

  test "loads a has_many association through the foreign key derived from the schema", %{
    customers: [customer1, customer2],
    invoices: [invoice1, invoice2]
  } do
    assert Relations.load(customer1, :invoices) == [invoice1, invoice2]
    assert Relations.load(customer2, :invoices) == []
  end

  test "loads a many_to_many association", %{
    cars: [car1, car2, car3],
    mechanics: [mechanic1, mechanic2]
  } do
    assert Relations.load(car1, :mechanics) == [mechanic1, mechanic2]
    assert Relations.load(car2, :mechanics) == [mechanic1]
    assert Relations.load(car3, :mechanics) == []

    assert Relations.load(mechanic1, :cars) == [car1, car2]
    assert Relations.load(mechanic2, :cars) == [car1]
    assert Relations.load(%Mechanic{id: 3, name: "Ivo"}, :cars) == []
  end

  test "loads a many_to_many association for many records at once", %{
    cars: [car1, car2, car3],
    mechanics: [mechanic1, mechanic2]
  } do
    assert Garage.batches() == 0

    assert Relations.load_many([car1, car2, car3], :mechanics) ==
             [{car1, [mechanic1, mechanic2]}, {car2, [mechanic1]}, {car3, []}]

    assert Garage.batches() == 2
  end

  test "loads a many_to_many association through the join keys it is given", %{
    customers: [customer1, customer2],
    dealers: [dealer1, dealer2]
  } do
    assert Relations.load(dealer1, :customers) == [customer1]
    assert Relations.load(dealer2, :customers) == [customer2]
    assert Relations.load(%Dealer{code: "CCC", name: "Cleo"}, :customers) == []
  end

  test "loads a belongs_to association", %{
    customers: [customer1, customer2],
    cars: [car1, car2, car3]
  } do
    assert Relations.load(car1, :owner) == customer1
    assert Relations.load(car2, :owner) == customer1
    assert Relations.load(car3, :owner) == customer2
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
    customers: [customer1, customer2],
    cars: [car1, car2, car3]
  } do
    stranger = %Customer{id: 3, name: "Ann"}

    assert [{^customer1, cars1}, {^customer2, cars2}, {^stranger, cars3}] =
             Relations.load_many([customer1, customer2, stranger], :cars)

    assert cars1 == [car1, car2]
    assert cars2 == [car3]
    assert cars3 == []
  end

  test "loads a belongs_to association for many records at once", %{
    customers: [customer1, customer2],
    cars: [car1, car2, car3]
  } do
    stray = %Car{id: 4, color: "green", owner_id: 3}

    assert Relations.load_many([car1, car2, car3, stray], :owner) ==
             [{car1, [customer1]}, {car2, [customer1]}, {car3, [customer2]}, {stray, []}]
  end

  test "keeps the order of the records it is given", %{
    customers: [customer1, customer2],
    cars: [car1, _car2, car3]
  } do
    assert Relations.load_many([car3, car1], :owner) == [{car3, [customer2]}, {car1, [customer1]}]

    assert [{^customer2, [^car3]}, {^customer1, _cars}] =
             Relations.load_many([customer2, customer1], :cars)

    assert Relations.load_many([car1, car1], :owner) == [{car1, [customer1]}, {car1, [customer1]}]
  end

  test "searches once for records that look for the same thing", %{cars: [car1, car2, _car3]} do
    assert Garage.searches() == 0

    Relations.load_many([car1, car1, car2], :owner)

    assert Garage.searches() == 1
  end

  test "loads the association of records of different schemas at once", %{
    customers: [customer1, _customer2],
    dealers: [dealer1, _dealer2],
    cars: [car1, car2, _car3]
  } do
    assert Garage.batches() == 0

    assert [{^customer1, cars1}, {^dealer1, cars2}] =
             Relations.load_many([customer1, dealer1], :cars)

    assert cars1 == [car1, car2]
    assert cars2 == [car1, car2]

    assert Garage.batches() == 1
  end

  test "finds nothing for a record whose key is nil", %{
    customers: [customer1, _customer2],
    cars: [car1, _car2, _car3]
  } do
    car = %Car{id: 4, color: "green", owner_id: nil}
    customer = %Customer{id: nil, name: "Nobody"}

    assert Relations.load(car, :owner) == nil
    assert Relations.load(customer, :cars) == []
    assert Relations.load_many([car, car1], :owner) == [{car, []}, {car1, [customer1]}]
  end

  test "keeps the associations a schema declares in more than one block", %{
    customers: [customer1, _customer2],
    cars: [car1, car2, _car3],
    invoices: [invoice1, invoice2]
  } do
    assert Relations.load(customer1, :cars) == [car1, car2]
    assert Relations.load(customer1, :invoices) == [invoice1, invoice2]
  end

  test "raises when a belongs_to association finds more than one record", %{
    customers: [customer1, _customer2],
    cars: [car1, _car2, _car3]
  } do
    Garage.put([%Customer{id: customer1.id, name: "John the second"}])

    assert_raise RuntimeError,
                 "the :owner association of Garage.Car found 2 records",
                 fn -> Relations.load(car1, :owner) end
  end

  test "raises for an association the schema does not declare", %{
    customers: [customer1, _customer2]
  } do
    message = "Garage.Customer has no :licences association"

    assert_raise ArgumentError, message, fn -> Relations.load(customer1, :licences) end
    assert_raise ArgumentError, message, fn -> Relations.load_many([customer1], :licences) end
  end

  test "returns no results for no records" do
    assert Relations.load_many([], :cars) == []
  end

  test "searches for every record in a single batch", %{customers: [customer1, customer2]} do
    assert Garage.batches() == 0

    Relations.load_many([customer1, customer2], :cars)

    assert Garage.batches() == 1

    Enum.map([customer1, customer2], &Relations.load(&1, :cars))

    assert Garage.batches() == 3
  end
end
