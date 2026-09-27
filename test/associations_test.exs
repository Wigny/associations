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

      Mox.expect(MockStore, :list, fn Garage.Customer, [:id], [[^owner_id]], [] ->
        [customer]
      end)

      assert Garage.load(car, :owner) == customer
    end

    test "loads a has_one association" do
      car_id = 1
      car = %Garage.Car{id: car_id}
      registration = %Garage.Registration{plate: "ABC123", car_id: car_id}

      Mox.expect(MockStore, :list, fn Garage.Registration, [:car_id], [[^car_id]], [] ->
        [registration]
      end)

      assert Garage.load(car, :registration) == registration
    end

    test "loads a has_many association" do
      owner_id = 1
      customer = %Garage.Customer{id: owner_id}

      car1 = %Garage.Car{id: 1, owner_id: owner_id}
      car2 = %Garage.Car{id: 2, owner_id: owner_id}

      Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], [[^owner_id]], [] ->
        [car1, car2]
      end)

      assert Garage.load(customer, :cars) == [car1, car2]
    end

    test "returns an empty list when a has_many association finds no record" do
      owner_id = 1
      customer = %Garage.Customer{id: owner_id}

      Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], [[^owner_id]], [] ->
        []
      end)

      assert Garage.load(customer, :cars) == []
    end

    test "loads a has_many association through the foreign key derived from the schema" do
      customer_id = 1
      customer = %Garage.Customer{id: customer_id}
      invoice = %Garage.Invoice{id: 1, total: 100, customer_id: customer_id}

      Mox.expect(MockStore, :list, fn Garage.Invoice, [:customer_id], [[^customer_id]], [] ->
        [invoice]
      end)

      assert Garage.load(customer, :invoices) == [invoice]
    end

    test "loads a belongs_to association referencing a field other than :id" do
      dealer_code = "AAA"
      dealer = %Garage.Dealer{code: dealer_code, name: "Anne"}
      car = %Garage.Car{id: 1, dealer_code: dealer_code}

      Mox.expect(MockStore, :list, fn Garage.Dealer, [:code], [[^dealer_code]], [] ->
        [dealer]
      end)

      assert Garage.load(car, :dealer) == dealer
    end

    test "loads a has_many association referencing a field other than :id" do
      dealer_code = "AAA"
      dealer = %Garage.Dealer{code: dealer_code, name: "Anne"}

      car1 = %Garage.Car{id: 1, dealer_code: dealer_code}
      car2 = %Garage.Car{id: 2, dealer_code: dealer_code}

      Mox.expect(MockStore, :list, fn Garage.Car, [:dealer_code], [[^dealer_code]], [] ->
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
                                      [[^manufacturer_code, ^part_number]],
                                      [] ->
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
                                      [[^manufacturer_code, ^part_number]],
                                      [] ->
        [usage1, usage2]
      end)

      assert Garage.load(part, :usages) == [usage1, usage2]
    end

    test "finds nothing for a record whose key is nil" do
      owner_id = nil
      car = %Garage.Car{id: 1, owner_id: owner_id}

      assert Garage.load(car, :owner) == nil
    end

    test "raises when a belongs_to association finds more than one record" do
      owner_id = 1
      car = %Garage.Car{id: 1, owner_id: owner_id}

      customer1 = %Garage.Customer{id: owner_id, name: "John"}
      customer2 = %Garage.Customer{id: owner_id, name: "Jane"}

      Mox.expect(MockStore, :list, fn Garage.Customer, [:id], [[^owner_id]], [] ->
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

      Mox.expect(MockStore, :list, fn Garage.Registration, [:car_id], [[^car_id]], [] ->
        [registration1, registration2]
      end)

      assert_raise RuntimeError,
                   "the :registration association of Garage.Car found 2 records",
                   fn -> Garage.load(car, :registration) end
    end

    test "raises for an association the schema does not declare" do
      assert_raise ArgumentError, "Garage.Customer has no :parts association", fn ->
        Garage.load(%Garage.Customer{id: 1}, :parts)
      end
    end

    test "raises for an association name that is not an atom" do
      assert_raise ArgumentError, "expected an association name, got: \"cars\"", fn ->
        Garage.load(%Garage.Customer{id: 1}, "cars")
      end
    end

    test "loads a has_many association through other associations without repeats" do
      owner_id = 1
      dealer_code = "AAA"

      customer = %Garage.Customer{id: owner_id}
      dealer = %Garage.Dealer{code: dealer_code, name: "Anne"}

      car1 = %Garage.Car{id: 1, owner_id: owner_id, dealer_code: dealer_code}
      car2 = %Garage.Car{id: 2, owner_id: owner_id, dealer_code: dealer_code}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id]], [] -> [car1, car2]
        Garage.Dealer, [:code], [[^dealer_code]], [] -> [dealer]
      end)

      assert Garage.load(customer, :dealers) == [dealer]
    end

    test "loads a has_one association through other associations as a single record" do
      car_id = 1
      owner_id = 2

      service = %Garage.Service{id: 1, cost: 100, car_id: car_id}
      car = %Garage.Car{id: car_id, owner_id: owner_id}
      customer = %Garage.Customer{id: owner_id, name: "John"}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:id], [[^car_id]], [] -> [car]
        Garage.Customer, [:id], [[^owner_id]], [] -> [customer]
      end)

      assert Garage.load(service, :owner) == customer
    end

    test "keeps the order the list call returned the records in" do
      owner_id = 1

      customer = %Garage.Customer{id: owner_id}

      car1 = %Garage.Car{id: 1, owner_id: owner_id, dealer_code: "AAA"}
      car2 = %Garage.Car{id: 2, owner_id: owner_id, dealer_code: "BBB"}

      anne = %Garage.Dealer{code: "AAA", name: "Anne"}
      bill = %Garage.Dealer{code: "BBB", name: "Bill"}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id]], [] -> [car1, car2]
        Garage.Dealer, [:code], [["AAA"], ["BBB"]], [] -> [bill, anne]
      end)

      assert Garage.load(customer, :dealers) == [bill, anne]
    end

    test "passes the args to the list call" do
      owner_id = 1

      Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], [[^owner_id]], args ->
        assert args == [color: "red"]

        []
      end)

      Garage.load(%Garage.Customer{id: owner_id}, :cars, args: [color: "red"])
    end

    test "lists every record reached through other associations in one call when given args" do
      owner_id = 1

      customer = %Garage.Customer{id: owner_id}

      car1 = %Garage.Car{id: 1, owner_id: owner_id, dealer_code: "AAA"}
      car2 = %Garage.Car{id: 2, owner_id: owner_id, dealer_code: "BBB"}

      anne = %Garage.Dealer{code: "AAA", name: "Anne"}
      bill = %Garage.Dealer{code: "BBB", name: "Bill"}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id]], _args ->
          [car1, car2]

        Garage.Dealer, [:code], values, [limit: limit] ->
          [anne, bill]
          |> Enum.filter(&([&1.code] in values))
          |> Enum.take(limit)
      end)

      assert Garage.load(customer, :dealers, args: [limit: 1]) == [anne]
    end

    test "lists the hops before the last without the args" do
      owner_id = 1

      car = %Garage.Car{id: 1, owner_id: owner_id, dealer_code: "AAA"}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id]], args ->
          assert args == []

          [car]

        Garage.Dealer, [:code], [["AAA"]], _args ->
          []
      end)

      Garage.load(%Garage.Customer{id: owner_id}, :dealers, args: [limit: 1])
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

      Mox.expect(MockStore, :list, fn Garage.Customer, [:id], [[^owner_id1], [^owner_id2]], [] ->
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

      Mox.expect(MockStore, :list, fn Garage.Registration,
                                      [:car_id],
                                      [[^car1_id], [^car2_id]],
                                      [] ->
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

      Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], [[^owner_id1], [^owner_id2]], [] ->
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

      Mox.expect(MockStore, :list, fn schema, fields, values, [] ->
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

      Mox.expect(MockStore, :list, 2, fn _schema, _fields, _values, _args ->
        send(caller, {:listed, self()})

        []
      end)

      Garage.load_many([customer, dealer], :cars)

      assert_received {:listed, pid1} when pid1 != caller
      assert_received {:listed, pid2} when pid2 != caller

      assert pid1 != pid2
    end

    test "loads an association through other associations" do
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
        Garage.Car, [:owner_id], [[^owner_id1], [^owner_id2]], [] -> [car1, car2]
        Garage.Dealer, [:code], [[^dealer_code1], [^dealer_code2]], [] -> [dealer1, dealer2]
      end)

      assert Garage.load_many([customer1, customer2], :dealers) == [
               {customer1, [dealer1]},
               {customer2, [dealer2]}
             ]
    end

    test "lists each record in a call of its own when given args" do
      owner_id1 = 1
      owner_id2 = 2

      customer1 = %Garage.Customer{id: owner_id1}
      customer2 = %Garage.Customer{id: owner_id2}

      car1 = %Garage.Car{id: 1, owner_id: owner_id1}
      car2 = %Garage.Car{id: 2, owner_id: owner_id1}
      car3 = %Garage.Car{id: 3, owner_id: owner_id2}

      Mox.expect(MockStore, :list, 2, fn Garage.Car, [:owner_id], values, [limit: limit] ->
        [car1, car2, car3]
        |> Enum.filter(&([&1.owner_id] in values))
        |> Enum.take(limit)
      end)

      assert Garage.load_many([customer1, customer2], :cars, args: [limit: 1]) == [
               {customer1, [car1]},
               {customer2, [car3]}
             ]
    end

    test "keeps the order of the records it is given" do
      owner_id1 = 1
      owner_id2 = 2

      customer1 = %Garage.Customer{id: owner_id1}
      customer2 = %Garage.Customer{id: owner_id2}

      car1 = %Garage.Car{id: 1, owner_id: owner_id1}
      car2 = %Garage.Car{id: 2, owner_id: owner_id2}

      Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], _values, [] -> [car1, car2] end)

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

      Mox.expect(MockStore, :list, fn schema, fields, values, [] ->
        assert schema == Garage.Customer
        assert fields == [:id]
        assert values == [[owner_id]]

        [customer]
      end)

      assert Garage.load_many([car1, car2], :owner) == [{car1, [customer]}, {car2, [customer]}]
    end

    test "lists records ending on the same rows in one call when given args" do
      owner_id = 1

      car1 = %Garage.Car{id: 1, owner_id: owner_id}
      car2 = %Garage.Car{id: 2, owner_id: owner_id}
      customer = %Garage.Customer{id: owner_id, name: "John"}

      Mox.expect(MockStore, :list, 1, fn Garage.Customer, [:id], [[^owner_id]], [limit: 1] ->
        [customer]
      end)

      assert Garage.load_many([car1, car2], :owner, args: [limit: 1]) == [
               {car1, [customer]},
               {car2, [customer]}
             ]
    end

    test "lists records ending on the same rows in a different order in one call when given args" do
      owner_id1 = 1
      owner_id2 = 2

      customer1 = %Garage.Customer{id: owner_id1}
      customer2 = %Garage.Customer{id: owner_id2}

      car1 = %Garage.Car{id: 1, owner_id: owner_id1, dealer_code: "AAA"}
      car2 = %Garage.Car{id: 2, owner_id: owner_id1, dealer_code: "BBB"}
      car3 = %Garage.Car{id: 3, owner_id: owner_id2, dealer_code: "BBB"}
      car4 = %Garage.Car{id: 4, owner_id: owner_id2, dealer_code: "AAA"}

      anne = %Garage.Dealer{code: "AAA", name: "Anne"}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id1], [^owner_id2]], [] ->
          [car1, car2, car3, car4]

        Garage.Dealer, [:code], [["AAA"], ["BBB"]], [limit: 1] ->
          [anne]
      end)

      assert Garage.load_many([customer1, customer2], :dealers, args: [limit: 1]) == [
               {customer1, [anne]},
               {customer2, [anne]}
             ]
    end

    test "loads the association of records of different schemas" do
      owner_id = 1
      dealer_code = "AAA"

      customer = %Garage.Customer{id: owner_id}
      dealer = %Garage.Dealer{code: dealer_code, name: "Anne"}

      car1 = %Garage.Car{id: 1, owner_id: owner_id}
      car2 = %Garage.Car{id: 2, dealer_code: dealer_code}

      Mox.expect(MockStore, :list, 2, fn
        Garage.Car, [:owner_id], [[^owner_id]], [] -> [car1]
        Garage.Car, [:dealer_code], [[^dealer_code]], [] -> [car2]
      end)

      assert Garage.load_many([customer, dealer], :cars) == [{customer, [car1]}, {dealer, [car2]}]
    end

    test "loads an association through other associations over records of different schemas" do
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
        Garage.Car, [:owner_id], [[^owner_id]], [] ->
          [car1]

        Garage.Car, [:dealer_code], [[^dealer_code]], [] ->
          [car2]

        Garage.Registration, [:car_id], [[^car1_id], [^car2_id]], [] ->
          [registration1, registration2]
      end)

      assert Garage.load_many([customer, dealer], :registrations) == [
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

    Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], [[^owner_id]], [] ->
      [car, other_car]
    end)

    assert Garage.load(customer, :cars) == [car]
  end

  test "lists in the process asking for it when async is false", %{test_pid: caller} do
    Mox.expect(MockStore, :list, fn _schema, _fields, _values, _args ->
      assert self() == caller

      []
    end)

    Garage.load(%Garage.Customer{id: 1}, :cars, async: false)
  end

  test "raises in the caller whatever the loader raised" do
    Mox.expect(MockStore, :list, fn _schema, _fields, _values, _args ->
      raise "the store is unreachable"
    end)

    assert_raise RuntimeError, "the store is unreachable", fn ->
      Garage.load(%Garage.Customer{id: 1}, :cars)
    end
  end

  test "raises in the caller whatever the loader raised when async is false" do
    Mox.expect(MockStore, :list, fn _schema, _fields, _values, _args ->
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
                     def list(_schema, _fields, _values, _args), do: []

                     association Garage.Usage do
                       belongs_to :part, Garage.Part,
                         foreign_key: [:manufacturer_code, :part_number],
                         references: :code
                     end
                   end
                 end
  end

  test "raises for an association going through one the schema along it does not declare" do
    assert_raise ArgumentError,
                 "the :usages association of Garage.Customer goes through :usages, which " <>
                   "Garage.Car does not declare as a belongs_to, has_many or has_one",
                 fn ->
                   defmodule Warehouse do
                     use Associations

                     @impl true
                     def list(_schema, _fields, _values, _args), do: []

                     association Garage.Customer do
                       has_many :cars, Garage.Car, foreign_key: :owner_id
                       has_many :usages, through: [:cars, :usages]
                     end
                   end
                 end
  end

  test "raises for a has_one association going through one holding many records" do
    assert_raise ArgumentError,
                 "the :registration association of Garage.Customer is a has_one, so it cannot " <>
                   "go through :cars of Garage.Customer, which holds many records",
                 fn ->
                   defmodule Warehouse do
                     use Associations

                     @impl true
                     def list(_schema, _fields, _values, _args), do: []

                     association Garage.Car do
                       has_one :registration, Garage.Registration
                     end

                     association Garage.Customer do
                       has_many :cars, Garage.Car, foreign_key: :owner_id
                       has_one :registration, through: [:cars, :registration]
                     end
                   end
                 end
  end

  test "raises for an association going through an empty list" do
    assert_raise ArgumentError,
                 "the :dealers association of Garage.Customer must go through a non-empty " <>
                   "list of associations, got: []",
                 fn ->
                   defmodule Warehouse do
                     use Associations

                     @impl true
                     def list(_schema, _fields, _values, _args), do: []

                     association Garage.Customer do
                       has_many :dealers, through: []
                     end
                   end
                 end
  end

  test "raises for an association going through another association declared with through" do
    assert_raise ArgumentError,
                 "the :dealers association of Garage.Invoice goes through :dealers, which " <>
                   "Garage.Customer does not declare as a belongs_to, has_many or has_one",
                 fn ->
                   defmodule Warehouse do
                     use Associations

                     @impl true
                     def list(_schema, _fields, _values, _args), do: []

                     association Garage.Car do
                       belongs_to :dealer, Garage.Dealer,
                         foreign_key: :dealer_code,
                         references: :code
                     end

                     association Garage.Customer do
                       has_many :cars, Garage.Car, foreign_key: :owner_id
                       has_many :dealers, through: [:cars, :dealer]
                     end

                     association Garage.Invoice do
                       belongs_to :customer, Garage.Customer
                       has_many :dealers, through: [:customer, :dealers]
                     end
                   end
                 end
  end

  defp stub_doctest_examples(context) do
    if context[:doctest], do: Mox.stub_with(MockStore, ExampleStore)

    :ok
  end
end
