defmodule AssociationsTest do
  use ExUnit.Case
  doctest Associations

  alias Garage.Car
  alias Garage.Compatibility
  alias Garage.Customer
  alias Garage.Dealer
  alias Garage.Invoice
  alias Garage.Mechanic
  alias Garage.Part
  alias Garage.Relations
  alias Garage.Service
  alias Garage.Usage

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
    part1 = %Part{manufacturer_code: "BOS", part_number: "12", name: "Oil filter"}
    part2 = %Part{manufacturer_code: "BOS", part_number: "34", name: "Spark plug"}
    part3 = %Part{manufacturer_code: "DEN", part_number: "12", name: "Timing belt"}
    usage1 = %Usage{service_id: 1, manufacturer_code: "BOS", part_number: "12", quantity: 1}
    usage2 = %Usage{service_id: 1, manufacturer_code: "DEN", part_number: "12", quantity: 2}
    usage3 = %Usage{service_id: 2, manufacturer_code: "BOS", part_number: "12", quantity: 1}
    fits1 = %Compatibility{car_id: 1, manufacturer_code: "BOS", part_number: "12"}
    fits2 = %Compatibility{car_id: 1, manufacturer_code: "DEN", part_number: "12"}
    fits3 = %Compatibility{car_id: 2, manufacturer_code: "BOS", part_number: "12"}

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
      service3,
      part1,
      part2,
      part3,
      usage1,
      usage2,
      usage3,
      fits1,
      fits2,
      fits3
    ])

    %{
      customers: [customer1, customer2],
      dealers: [dealer1, dealer2],
      cars: [car1, car2, car3],
      invoices: [invoice1, invoice2],
      mechanics: [mechanic1, mechanic2],
      services: [service1, service2, service3],
      parts: [part1, part2, part3],
      usages: [usage1, usage2, usage3]
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

    assert Garage.batches() == 2
  end

  test "loads a belongs_to association keyed on more than one field", %{
    parts: [part1, _part2, part3],
    usages: [usage1, usage2, _usage3]
  } do
    stray = %Usage{service_id: 3, manufacturer_code: "BOS", part_number: "99", quantity: 1}

    assert Relations.load(usage1, :part) == part1
    assert Relations.load(usage2, :part) == part3
    assert Relations.load(stray, :part) == nil
  end

  test "loads a has_many association keyed on more than one field", %{
    parts: [part1, part2, part3],
    usages: [usage1, usage2, usage3]
  } do
    assert Relations.load(part1, :usages) == [usage1, usage3]
    assert Relations.load(part2, :usages) == []
    assert Relations.load(part3, :usages) == [usage2]
  end

  test "loads a many_to_many association whose join keys hold more than one field", %{
    cars: [car1, car2, car3],
    parts: [part1, _part2, part3]
  } do
    assert Relations.load(car1, :compatible_parts) == [part1, part3]
    assert Relations.load(car2, :compatible_parts) == [part1]
    assert Relations.load(car3, :compatible_parts) == []
  end

  test "fetches every row a set of fields is searched by in a single call", %{
    parts: [part1, _part2, part3]
  } do
    Relations.load_many([part1, part3], :usages)

    assert Garage.calls() == [
             {Usage, [:manufacturer_code, :part_number], [["BOS", "12"], ["DEN", "12"]]}
           ]
  end

  test "raises for an association pairing a different number of fields" do
    message =
      ~s(the :part association of Garage.Usage pairs [:manufacturer_code, :part_number] ) <>
        ~s(with [:part_number], which name a different number of fields)

    assert_raise ArgumentError, message, fn ->
      defmodule Broken do
        use Associations

        @impl true
        def fetch(_schema, _fields, _values), do: []

        association Usage do
          belongs_to :part, Part,
            foreign_key: [:manufacturer_code, :part_number],
            references: [:part_number]
        end
      end
    end
  end

  test "fetches every value a field is searched by in a single call", %{
    customers: [customer1, customer2],
    dealers: [dealer1, _dealer2]
  } do
    Relations.load_many([customer1, customer2, dealer1], :cars)

    assert Garage.calls() == [
             {Car, [:owner_id], [[1], [2]]},
             {Car, [:dealer_code], [["AAA"]]}
           ]
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

  test "loads a path of associations", %{
    customers: [customer1, customer2],
    mechanics: [mechanic1, mechanic2]
  } do
    assert Relations.load(customer1, [:cars, :mechanics]) == [mechanic1, mechanic2]
    assert Relations.load(customer2, [:cars, :mechanics]) == []
    assert Relations.load(%Customer{id: 3, name: "Ann"}, [:cars, :mechanics]) == []
  end

  test "loads a path of one association", %{
    customers: [customer1, _customer2],
    cars: [car1, car2, _car3]
  } do
    assert Relations.load(customer1, [:cars]) == [car1, car2]
    assert Relations.load(car1, [:owner]) == customer1

    assert Relations.load_many([car1, car2], [:owner]) == [
             {car1, [customer1]},
             {car2, [customer1]}
           ]
  end

  test "returns a single record for a path of belongs_to associations", %{
    customers: [customer1, customer2],
    services: [service1, _service2, service3]
  } do
    assert Relations.load(service1, [:car, :owner]) == customer1
    assert Relations.load(service3, [:car, :owner]) == customer1
    assert Relations.load(%Service{id: 4, cost: 10, car_id: 3}, [:car, :owner]) == customer2
    assert Relations.load(%Service{id: 4, cost: 10, car_id: nil}, [:car, :owner]) == nil
    assert Relations.load(%Service{id: 4, cost: 10, car_id: 9}, [:car, :owner]) == nil
  end

  test "returns a list for a path holding an association other than belongs_to", %{
    customers: [customer1, _customer2],
    dealers: [dealer1, _dealer2]
  } do
    assert Relations.load(dealer1, [:cars, :owner]) == [customer1]
  end

  test "dedups the records a path converges on", %{
    customers: [customer1, customer2],
    cars: [_car1, _car2, car3],
    mechanics: [mechanic1, mechanic2]
  } do
    Garage.put([%Service{id: 4, cost: 20, car_id: car3.id, mechanic_id: mechanic1.id}])

    assert Relations.load_many([customer1, customer2], [:cars, :mechanics]) ==
             [{customer1, [mechanic1, mechanic2]}, {customer2, [mechanic1]}]
  end

  test "loads a path for many records at once", %{
    customers: [customer1, customer2],
    mechanics: [mechanic1, mechanic2]
  } do
    stranger = %Customer{id: 3, name: "Ann"}

    assert Relations.load_many([customer2, customer1, stranger], [:cars, :mechanics]) ==
             [{customer2, []}, {customer1, [mechanic1, mechanic2]}, {stranger, []}]
  end

  test "searches once per hop of a path", %{customers: [customer1, customer2]} do
    assert Garage.batches() == 0

    Relations.load_many([customer1, customer2], [:cars, :mechanics])

    assert Garage.batches() == 3
  end

  test "loads a path over records of different schemas at once", %{
    customers: [customer1, _customer2],
    dealers: [dealer1, _dealer2],
    mechanics: [mechanic1, mechanic2]
  } do
    assert Relations.load_many([customer1, dealer1], [:cars, :mechanics]) ==
             [{customer1, [mechanic1, mechanic2]}, {dealer1, [mechanic1, mechanic2]}]
  end

  test "raises for an association a schema along the path does not declare", %{
    customers: [customer1, _customer2]
  } do
    message = "Garage.Car has no :licences association"

    assert_raise ArgumentError, message, fn -> Relations.load(customer1, [:cars, :licences]) end

    assert_raise ArgumentError, message, fn ->
      Relations.load_many([customer1], [:cars, :licences])
    end
  end

  test "raises for an empty path", %{customers: [customer1, _customer2]} do
    message = "an association path must hold at least one association"

    assert_raise ArgumentError, message, fn -> Relations.load(customer1, []) end
    assert_raise ArgumentError, message, fn -> Relations.load_many([customer1], []) end
  end

  test "raises when a path of belongs_to associations finds more than one record", %{
    customers: [customer1, _customer2],
    services: [service1, _service2, _service3]
  } do
    Garage.put([%Customer{id: customer1.id, name: "John the second"}])

    assert_raise RuntimeError,
                 "the [:car, :owner] association of Garage.Service found 2 records",
                 fn -> Relations.load(service1, [:car, :owner]) end
  end
end
