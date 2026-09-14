defmodule AssociationsTest do
  use ExUnit.Case, async: true

  setup {Mox, :verify_on_exit!}
  setup :stub_doctest_examples

  doctest Associations
  doctest Garage

  describe "load/2" do
    test "loads a belongs_to association" do
      owner_id = 1
      customer = %Garage.Customer{id: owner_id}
      car = %Garage.Car{id: 1, owner_id: owner_id}

      Mox.expect(MockStore, :list, fn Garage.Customer, [:id], [[^owner_id]] ->
        [customer]
      end)

      assert Garage.load(car, :owner) == customer
    end

    test "loads a has_one association" do
      car_id = 1
      car = %Garage.Car{id: car_id}
      registration = %Garage.Registration{plate: "ABC123", car_id: car_id}

      Mox.expect(MockStore, :list, fn Garage.Registration, [:car_id], [[^car_id]] ->
        [registration]
      end)

      assert Garage.load(car, :registration) == registration
    end

    test "loads a has_many association" do
      owner_id = 1
      customer = %Garage.Customer{id: owner_id}

      car1 = %Garage.Car{id: 1, owner_id: owner_id}
      car2 = %Garage.Car{id: 2, owner_id: owner_id}

      Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], [[^owner_id]] ->
        [car1, car2]
      end)

      assert Garage.load(customer, :cars) == [car1, car2]
    end

    test "returns an empty list when a has_many association finds no record" do
      owner_id = 1
      customer = %Garage.Customer{id: owner_id}

      Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], [[^owner_id]] ->
        []
      end)

      assert Garage.load(customer, :cars) == []
    end

    test "loads a has_many association through the foreign key derived from the schema" do
      customer_id = 1
      customer = %Garage.Customer{id: customer_id}
      invoice = %Garage.Invoice{id: 1, total: 100, customer_id: customer_id}

      Mox.expect(MockStore, :list, fn Garage.Invoice, [:customer_id], [[^customer_id]] ->
        [invoice]
      end)

      assert Garage.load(customer, :invoices) == [invoice]
    end

    test "loads a belongs_to association referencing a field other than :id" do
      dealer_code = "AAA"
      dealer = %Garage.Dealer{code: dealer_code, name: "Anne"}
      car = %Garage.Car{id: 1, dealer_code: dealer_code}

      Mox.expect(MockStore, :list, fn Garage.Dealer, [:code], [[^dealer_code]] ->
        [dealer]
      end)

      assert Garage.load(car, :dealer) == dealer
    end

    test "loads a has_many association referencing a field other than :id" do
      dealer_code = "AAA"
      dealer = %Garage.Dealer{code: dealer_code, name: "Anne"}

      car1 = %Garage.Car{id: 1, dealer_code: dealer_code}
      car2 = %Garage.Car{id: 2, dealer_code: dealer_code}

      Mox.expect(MockStore, :list, fn Garage.Car, [:dealer_code], [[^dealer_code]] ->
        [car1, car2]
      end)

      assert Garage.load(dealer, :cars) == [car1, car2]
    end

    test "loads a belongs_to association keyed on more than one field" do
      manufacturer_code = "BOSCH"
      part_number = "0242"

      part = %Garage.Part{
        manufacturer_code: manufacturer_code,
        part_number: part_number,
        name: "Spark plug"
      }

      compatibility = %Garage.Compatibility{
        car_id: 1,
        manufacturer_code: manufacturer_code,
        part_number: part_number
      }

      Mox.expect(MockStore, :list, fn Garage.Part,
                                      [:manufacturer_code, :part_number],
                                      [[^manufacturer_code, ^part_number]] ->
        [part]
      end)

      assert Garage.load(compatibility, :part) == part
    end

    test "loads a has_many association keyed on more than one field" do
      manufacturer_code = "BOSCH"
      part_number = "0242"

      part = %Garage.Part{
        manufacturer_code: manufacturer_code,
        part_number: part_number,
        name: "Spark plug"
      }

      usage1 = %Garage.Usage{
        service_id: 1,
        manufacturer_code: manufacturer_code,
        part_number: part_number,
        quantity: 4
      }

      usage2 = %Garage.Usage{
        service_id: 2,
        manufacturer_code: manufacturer_code,
        part_number: part_number,
        quantity: 2
      }

      Mox.expect(MockStore, :list, fn Garage.Usage,
                                      [:manufacturer_code, :part_number],
                                      [[^manufacturer_code, ^part_number]] ->
        [usage1, usage2]
      end)

      assert Garage.load(part, :usages) == [usage1, usage2]
    end

    test "finds nothing for a record whose key is nil" do
      owner_id = nil
      car = %Garage.Car{id: 1, owner_id: owner_id}

      Mox.expect(MockStore, :list, fn Garage.Customer, [:id], [[^owner_id]] -> [] end)

      assert Garage.load(car, :owner) == nil
    end

    test "raises when a belongs_to association finds more than one record" do
      owner_id = 1
      car = %Garage.Car{id: 1, owner_id: owner_id}

      customer1 = %Garage.Customer{id: owner_id, name: "John"}
      customer2 = %Garage.Customer{id: owner_id, name: "Jane"}

      Mox.expect(MockStore, :list, fn Garage.Customer, [:id], [[^owner_id]] ->
        [customer1, customer2]
      end)

      assert_raise RuntimeError, "the :owner association of Garage.Car found 2 records", fn ->
        Garage.load(car, :owner)
      end
    end

    test "raises when a has_one association finds more than one record" do
      car_id = 1
      car = %Garage.Car{id: car_id}

      registration1 = %Garage.Registration{plate: "ABC123", car_id: car_id}
      registration2 = %Garage.Registration{plate: "XYZ789", car_id: car_id}

      Mox.expect(MockStore, :list, fn Garage.Registration, [:car_id], [[^car_id]] ->
        [registration1, registration2]
      end)

      assert_raise RuntimeError,
                   "the :registration association of Garage.Car found 2 records",
                   fn -> Garage.load(car, :registration) end
    end

    test "raises for an association the schema does not declare" do
      assert_raise ArgumentError, "Garage.Customer has no :dealers association", fn ->
        Garage.load(%Garage.Customer{id: 1}, :dealers)
      end
    end

    test "loads a path of associations" do
      owner_id = 1
      car1_id = 1
      car2_id = 2

      customer = %Garage.Customer{id: owner_id}

      car1 = %Garage.Car{id: car1_id, owner_id: owner_id}
      car2 = %Garage.Car{id: car2_id, owner_id: owner_id}

      service1 = %Garage.Service{id: 1, cost: 100, car_id: car1_id}
      service2 = %Garage.Service{id: 2, cost: 200, car_id: car2_id}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id]] -> [car1, car2]
        Garage.Service, [:car_id], [[^car1_id], [^car2_id]] -> [service1, service2]
      end)

      assert Garage.load(customer, [:cars, :services]) == [service1, service2]
    end

    test "loads a path whose hops key on fields other than :id" do
      owner_id = 1
      dealer_code = "AAA"

      customer = %Garage.Customer{id: owner_id}
      dealer = %Garage.Dealer{code: dealer_code, name: "Anne"}
      car = %Garage.Car{id: 1, owner_id: owner_id, dealer_code: dealer_code}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id]] -> [car]
        Garage.Dealer, [:code], [[^dealer_code]] -> [dealer]
      end)

      assert Garage.load(customer, [:cars, :dealer]) == [dealer]
    end

    test "loads a path whose hops key on more than one field" do
      car_id = 1
      manufacturer_code = "BOSCH"
      part_number = "0242"

      car = %Garage.Car{id: car_id}

      part = %Garage.Part{
        manufacturer_code: manufacturer_code,
        part_number: part_number,
        name: "Spark plug"
      }

      compatibility = %Garage.Compatibility{
        car_id: car_id,
        manufacturer_code: manufacturer_code,
        part_number: part_number
      }

      Mox.expect(MockStore, :list, 2, fn
        Garage.Compatibility, [:car_id], [[^car_id]] ->
          [compatibility]

        Garage.Part, [:manufacturer_code, :part_number], [[^manufacturer_code, ^part_number]] ->
          [part]
      end)

      assert Garage.load(car, [:compatibilities, :part]) == [part]
    end

    test "returns a single record for a path of belongs_to associations" do
      car_id = 1
      owner_id = 2

      service = %Garage.Service{id: 1, cost: 100, car_id: car_id}
      car = %Garage.Car{id: car_id, owner_id: owner_id}
      customer = %Garage.Customer{id: owner_id, name: "John"}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:id], [[^car_id]] -> [car]
        Garage.Customer, [:id], [[^owner_id]] -> [customer]
      end)

      assert Garage.load(service, [:car, :owner]) == customer
    end

    test "returns a single record for a path of belongs_to and has_one associations" do
      car_id = 1

      service = %Garage.Service{id: 1, cost: 100, car_id: car_id}
      car = %Garage.Car{id: car_id}
      registration = %Garage.Registration{plate: "ABC123", car_id: car_id}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:id], [[^car_id]] -> [car]
        Garage.Registration, [:car_id], [[^car_id]] -> [registration]
      end)

      assert Garage.load(service, [:car, :registration]) == registration
    end

    test "returns a list for a path holding a has_one after a has_many" do
      owner_id = 1
      car_id = 2

      customer = %Garage.Customer{id: owner_id}
      car = %Garage.Car{id: car_id, owner_id: owner_id}
      registration = %Garage.Registration{plate: "ABC123", car_id: car_id}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id]] -> [car]
        Garage.Registration, [:car_id], [[^car_id]] -> [registration]
      end)

      assert Garage.load(customer, [:cars, :registration]) == [registration]
    end

    test "dedups the records a path converges on" do
      owner_id = 1
      dealer_code = "AAA"

      customer = %Garage.Customer{id: owner_id}
      dealer = %Garage.Dealer{code: dealer_code, name: "Anne"}

      car1 = %Garage.Car{id: 1, owner_id: owner_id, dealer_code: dealer_code}
      car2 = %Garage.Car{id: 2, owner_id: owner_id, dealer_code: dealer_code}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id]] -> [car1, car2]
        Garage.Dealer, [:code], [[^dealer_code]] -> [dealer]
      end)

      assert Garage.load(customer, [:cars, :dealer]) == [dealer]
    end

    test "raises for an association a schema along the path does not declare" do
      assert_raise ArgumentError, "Garage.Car has no :usages association", fn ->
        Garage.load(%Garage.Customer{id: 1}, [:cars, :usages])
      end
    end

    test "raises for an empty path" do
      assert_raise ArgumentError, "an association path must hold at least one association", fn ->
        Garage.load(%Garage.Customer{id: 1}, [])
      end
    end

    test "raises when a path of belongs_to associations finds more than one record" do
      car_id = 1
      owner_id = 2

      service = %Garage.Service{id: 1, cost: 100, car_id: car_id}
      car = %Garage.Car{id: car_id, owner_id: owner_id}

      customer1 = %Garage.Customer{id: owner_id, name: "John"}
      customer2 = %Garage.Customer{id: owner_id, name: "Jane"}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:id], [[^car_id]] -> [car]
        Garage.Customer, [:id], [[^owner_id]] -> [customer1, customer2]
      end)

      assert_raise RuntimeError,
                   "the [:car, :owner] association of Garage.Service found 2 records",
                   fn -> Garage.load(service, [:car, :owner]) end
    end
  end

  describe "load_many/2" do
    test "loads a belongs_to association" do
      owner_id1 = 1
      owner_id2 = 2

      car1 = %Garage.Car{id: 1, owner_id: owner_id1}
      car2 = %Garage.Car{id: 2, owner_id: owner_id2}

      customer1 = %Garage.Customer{id: owner_id1, name: "John"}
      customer2 = %Garage.Customer{id: owner_id2, name: "Jane"}

      Mox.expect(MockStore, :list, fn Garage.Customer, [:id], [[^owner_id1], [^owner_id2]] ->
        [customer1, customer2]
      end)

      assert Garage.load_many([car1, car2], :owner) == [
               {car1, [customer1]},
               {car2, [customer2]}
             ]
    end

    test "loads a has_one association" do
      car1_id = 1
      car2_id = 2

      car1 = %Garage.Car{id: car1_id}
      car2 = %Garage.Car{id: car2_id}

      registration1 = %Garage.Registration{plate: "ABC123", car_id: car1_id}
      registration2 = %Garage.Registration{plate: "XYZ789", car_id: car2_id}

      Mox.expect(MockStore, :list, fn Garage.Registration, [:car_id], [[^car1_id], [^car2_id]] ->
        [registration1, registration2]
      end)

      assert Garage.load_many([car1, car2], :registration) == [
               {car1, [registration1]},
               {car2, [registration2]}
             ]
    end

    test "loads a has_many association" do
      owner_id1 = 1
      owner_id2 = 2

      customer1 = %Garage.Customer{id: owner_id1}
      customer2 = %Garage.Customer{id: owner_id2}

      car1 = %Garage.Car{id: 1, owner_id: owner_id1}
      car2 = %Garage.Car{id: 2, owner_id: owner_id1}
      car3 = %Garage.Car{id: 3, owner_id: owner_id2}

      Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], [[^owner_id1], [^owner_id2]] ->
        [car1, car2, car3]
      end)

      assert Garage.load_many([customer1, customer2], :cars) == [
               {customer1, [car1, car2]},
               {customer2, [car3]}
             ]
    end

    test "lists every value a field is searched by in a single call" do
      owner_id1 = 1
      owner_id2 = 2

      customer1 = %Garage.Customer{id: owner_id1}
      customer2 = %Garage.Customer{id: owner_id2}

      Mox.expect(MockStore, :list, fn schema, fields, values ->
        assert schema == Garage.Car
        assert fields == [:owner_id]
        assert values == [[owner_id1], [owner_id2]]

        []
      end)

      assert Garage.load_many([customer1, customer2], :cars) == [{customer1, []}, {customer2, []}]
    end

    test "lists the groups of a hop in a process of their own", %{test_pid: caller} do
      customer = %Garage.Customer{id: 1}
      dealer = %Garage.Dealer{code: "AAA", name: "Anne"}

      Mox.expect(MockStore, :list, 2, fn _schema, _fields, _values ->
        send(caller, {:listed, self()})

        []
      end)

      Garage.load_many([customer, dealer], :cars)

      assert_received {:listed, pid1} when pid1 != caller
      assert_received {:listed, pid2} when pid2 != caller

      assert pid1 != pid2
    end

    test "loads a path" do
      owner_id1 = 1
      owner_id2 = 2
      dealer_code1 = "AAA"
      dealer_code2 = "BBB"

      customer1 = %Garage.Customer{id: owner_id1}
      customer2 = %Garage.Customer{id: owner_id2}

      car1 = %Garage.Car{id: 1, owner_id: owner_id1, dealer_code: dealer_code1}
      car2 = %Garage.Car{id: 2, owner_id: owner_id2, dealer_code: dealer_code2}

      dealer1 = %Garage.Dealer{code: dealer_code1, name: "Anne"}
      dealer2 = %Garage.Dealer{code: dealer_code2, name: "Bill"}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id1], [^owner_id2]] -> [car1, car2]
        Garage.Dealer, [:code], [[^dealer_code1], [^dealer_code2]] -> [dealer1, dealer2]
      end)

      assert Garage.load_many([customer1, customer2], [:cars, :dealer]) == [
               {customer1, [dealer1]},
               {customer2, [dealer2]}
             ]
    end

    test "keeps the order of the records it is given" do
      owner_id1 = 1
      owner_id2 = 2

      customer1 = %Garage.Customer{id: owner_id1}
      customer2 = %Garage.Customer{id: owner_id2}

      car1 = %Garage.Car{id: 1, owner_id: owner_id1}
      car2 = %Garage.Car{id: 2, owner_id: owner_id2}

      Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], _values -> [car1, car2] end)

      assert Garage.load_many([customer2, customer1], :cars) == [
               {customer2, [car2]},
               {customer1, [car1]}
             ]
    end

    test "returns an empty list for no records" do
      assert Garage.load_many([], :cars) == []
    end

    test "searches once for records that look for the same thing" do
      owner_id = 1

      car1 = %Garage.Car{id: 1, owner_id: owner_id}
      car2 = %Garage.Car{id: 2, owner_id: owner_id}
      customer = %Garage.Customer{id: owner_id, name: "John"}

      Mox.expect(MockStore, :list, fn schema, fields, values ->
        assert schema == Garage.Customer
        assert fields == [:id]
        assert values == [[owner_id]]

        [customer]
      end)

      assert Garage.load_many([car1, car2], :owner) == [{car1, [customer]}, {car2, [customer]}]
    end

    test "loads the association of records of different schemas" do
      owner_id = 1
      dealer_code = "AAA"

      customer = %Garage.Customer{id: owner_id}
      dealer = %Garage.Dealer{code: dealer_code, name: "Anne"}

      car1 = %Garage.Car{id: 1, owner_id: owner_id}
      car2 = %Garage.Car{id: 2, dealer_code: dealer_code}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id]] -> [car1]
        Garage.Car, [:dealer_code], [[^dealer_code]] -> [car2]
      end)

      assert Garage.load_many([customer, dealer], :cars) == [{customer, [car1]}, {dealer, [car2]}]
    end

    test "loads a path over records of different schemas" do
      owner_id = 1
      dealer_code = "AAA"
      car1_id = 1
      car2_id = 2

      customer = %Garage.Customer{id: owner_id}
      dealer = %Garage.Dealer{code: dealer_code, name: "Anne"}

      car1 = %Garage.Car{id: car1_id, owner_id: owner_id}
      car2 = %Garage.Car{id: car2_id, dealer_code: dealer_code}

      registration1 = %Garage.Registration{plate: "ABC123", car_id: car1_id}
      registration2 = %Garage.Registration{plate: "XYZ789", car_id: car2_id}

      Mox.expect(MockStore, :list, 3, fn
        Garage.Car, [:owner_id], [[^owner_id]] ->
          [car1]

        Garage.Car, [:dealer_code], [[^dealer_code]] ->
          [car2]

        Garage.Registration, [:car_id], [[^car1_id], [^car2_id]] ->
          [registration1, registration2]
      end)

      assert Garage.load_many([customer, dealer], [:cars, :registration]) == [
               {customer, [registration1]},
               {dealer, [registration2]}
             ]
    end
  end

  test "ignores a record matching none of the rows it was asked for" do
    owner_id = 1
    customer = %Garage.Customer{id: owner_id}
    car = %Garage.Car{id: 1, owner_id: owner_id}
    other_car = %Garage.Car{id: 2, owner_id: 2}

    Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], [[^owner_id]] ->
      [car, other_car]
    end)

    assert Garage.load(customer, :cars) == [car]
  end

  test "lists in the process asking for it when async is false", %{test_pid: caller} do
    Mox.expect(MockStore, :list, fn _schema, _fields, _values ->
      assert self() == caller

      []
    end)

    Garage.load(%Garage.Customer{id: 1}, :cars, async: false)
  end

  test "raises in the caller whatever the loader raised" do
    Mox.expect(MockStore, :list, fn _schema, _fields, _values ->
      raise "the store is unreachable"
    end)

    assert_raise RuntimeError, "the store is unreachable", fn ->
      Garage.load(%Garage.Customer{id: 1}, :cars)
    end
  end

  test "raises in the caller whatever the loader raised when async is false" do
    Mox.expect(MockStore, :list, fn _schema, _fields, _values ->
      raise "the store is unreachable"
    end)

    assert_raise RuntimeError, "the store is unreachable", fn ->
      Garage.load(%Garage.Customer{id: 1}, :cars, async: false)
    end
  end

  test "raises for an association pairing a different number of fields" do
    assert_raise ArgumentError,
                 "the :part association of Garage.Usage pairs [:manufacturer_code, :part_number] " <>
                   "with [:code], which name a different number of fields",
                 fn ->
                   defmodule Warehouse do
                     use Associations

                     @impl true
                     def list(_schema, _fields, _values), do: []

                     association Garage.Usage do
                       belongs_to :part, Garage.Part,
                         foreign_key: [:manufacturer_code, :part_number],
                         references: :code
                     end
                   end
                 end
  end

  defp stub_doctest_examples(context) do
    if context[:doctest], do: Mox.stub_with(MockStore, ExampleStore)

    :ok
  end
end
