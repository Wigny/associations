defmodule Associations.DataloaderTest do
  use ExUnit.Case, async: true

  setup {Mox, :verify_on_exit!}

  setup do
    Mox.stub_with(MockStore, ExampleStore)

    source = Associations.Dataloader.new(Garage)
    %{loader: Dataloader.add_source(Dataloader.new(), :garage, source)}
  end

  describe "loading" do
    test "loads a has_many association as a list", %{loader: loader} do
      customer = %Garage.Customer{id: 1, name: "John"}

      loader =
        loader
        |> Dataloader.load(:garage, :cars, customer)
        |> Dataloader.run()

      assert Dataloader.get(loader, :garage, :cars, customer) == [
               %Garage.Car{id: 1, color: "red", owner_id: 1, dealer_code: "AAA"},
               %Garage.Car{id: 2, color: "yellow", owner_id: 1, dealer_code: "AAA"}
             ]
    end

    test "loads a belongs_to association as a single record", %{loader: loader} do
      car = %Garage.Car{id: 1, color: "red", owner_id: 1, dealer_code: "AAA"}

      loader =
        loader
        |> Dataloader.load(:garage, :owner, car)
        |> Dataloader.run()

      assert Dataloader.get(loader, :garage, :owner, car) == %Garage.Customer{id: 1, name: "John"}
    end

    test "loads a belongs_to association finding no record as nil", %{loader: loader} do
      car = %Garage.Car{id: 4, owner_id: 3}

      loader =
        loader
        |> Dataloader.load(:garage, :owner, car)
        |> Dataloader.run()

      assert Dataloader.get(loader, :garage, :owner, car) == nil
    end

    test "loads a path ending on a has_many association as a list", %{loader: loader} do
      customer = %Garage.Customer{id: 1, name: "John"}

      loader =
        loader
        |> Dataloader.load(:garage, [:cars, :dealer], customer)
        |> Dataloader.run()

      assert Dataloader.get(loader, :garage, [:cars, :dealer], customer) == [
               %Garage.Dealer{code: "AAA", name: "Anne"}
             ]
    end

    test "loads a path made of single associations as a single record", %{loader: loader} do
      service = %Garage.Service{id: 1, car_id: 1}

      loader =
        loader
        |> Dataloader.load(:garage, [:car, :owner], service)
        |> Dataloader.run()

      assert Dataloader.get(loader, :garage, [:car, :owner], service) ==
               %Garage.Customer{id: 1, name: "John"}
    end
  end

  describe "batching" do
    test "loads every record queued under a path in one fetch", %{loader: loader} do
      customer1 = %Garage.Customer{id: 1, name: "John"}
      customer2 = %Garage.Customer{id: 2, name: "Jane"}

      Mox.expect(MockStore, :list, fn Garage.Car, [:owner_id], values ->
        assert Enum.sort(values) == [[1], [2]]

        ExampleStore.list(Garage.Car, [:owner_id], values)
      end)

      loader =
        loader
        |> Dataloader.load(:garage, :cars, customer1)
        |> Dataloader.load(:garage, :cars, customer2)
        |> Dataloader.run()

      assert Dataloader.get(loader, :garage, :cars, customer1) == [
               %Garage.Car{id: 1, color: "red", owner_id: 1, dealer_code: "AAA"},
               %Garage.Car{id: 2, color: "yellow", owner_id: 1, dealer_code: "AAA"}
             ]

      assert Dataloader.get(loader, :garage, :cars, customer2) == [
               %Garage.Car{id: 3, color: "blue", owner_id: 2, dealer_code: "BBB"}
             ]
    end

    test "loads records of different schemas queued under a path together", %{loader: loader} do
      customer = %Garage.Customer{id: 2, name: "Jane"}
      dealer = %Garage.Dealer{code: "AAA", name: "Anne"}

      loader =
        loader
        |> Dataloader.load(:garage, :cars, customer)
        |> Dataloader.load(:garage, :cars, dealer)
        |> Dataloader.run()

      assert Dataloader.get(loader, :garage, :cars, customer) == [
               %Garage.Car{id: 3, color: "blue", owner_id: 2, dealer_code: "BBB"}
             ]

      assert Dataloader.get(loader, :garage, :cars, dealer) == [
               %Garage.Car{id: 1, color: "red", owner_id: 1, dealer_code: "AAA"},
               %Garage.Car{id: 2, color: "yellow", owner_id: 1, dealer_code: "AAA"}
             ]
    end

    test "does not fetch a record loaded by an earlier run again", %{loader: loader} do
      customer = %Garage.Customer{id: 2, name: "Jane"}

      Mox.expect(MockStore, :list, 1, &ExampleStore.list/3)

      loader =
        loader
        |> Dataloader.load(:garage, :cars, customer)
        |> Dataloader.run()
        |> Dataloader.load(:garage, :cars, customer)

      refute Dataloader.pending_batches?(loader)

      assert Dataloader.get(Dataloader.run(loader), :garage, :cars, customer) == [
               %Garage.Car{id: 3, color: "blue", owner_id: 2, dealer_code: "BBB"}
             ]
    end

    test "does not fetch a record put into the results", %{loader: loader} do
      customer = %Garage.Customer{id: 2, name: "Jane"}
      car = %Garage.Car{id: 4, color: "green", owner_id: 2}

      Mox.expect(MockStore, :list, 0, &ExampleStore.list/3)

      loader =
        loader
        |> Dataloader.put(:garage, :cars, customer, [car])
        |> Dataloader.load(:garage, :cars, customer)
        |> Dataloader.run()

      assert Dataloader.get(loader, :garage, :cars, customer) == [car]
    end
  end

  describe "batch keys" do
    test "accepts a {path, args} pair with empty args", %{loader: loader} do
      customer = %Garage.Customer{id: 2, name: "Jane"}

      loader =
        loader
        |> Dataloader.load(:garage, {:cars, %{}}, customer)
        |> Dataloader.run()

      assert Dataloader.get(loader, :garage, {:cars, %{}}, customer) == [
               %Garage.Car{id: 3, color: "blue", owner_id: 2, dealer_code: "BBB"}
             ]
    end

    test "raises for a {path, args} pair with args", %{loader: loader} do
      customer = %Garage.Customer{id: 1, name: "John"}

      assert_raise ArgumentError,
                   "Associations.Dataloader cannot apply the arguments %{color: \"red\"} to the " <>
                     ":cars association",
                   fn -> Dataloader.load(loader, :garage, {:cars, %{color: "red"}}, customer) end
    end

    test "raises for a batch key that is not a path", %{loader: loader} do
      customer = %Garage.Customer{id: 1, name: "John"}

      assert_raise ArgumentError,
                   "expected an association path or a {path, args} pair as the batch key, got: " <>
                     "\"cars\"",
                   fn -> Dataloader.load(loader, :garage, "cars", customer) end
    end
  end

  describe "errors" do
    setup do
      source = Associations.Dataloader.new(Garage)

      %{loader: Dataloader.add_source(Dataloader.new(get_policy: :tuples), :garage, source)}
    end

    @tag :capture_log
    test "returns an error for a record of a batch that raised", %{loader: loader} do
      customer = %Garage.Customer{id: 1, name: "John"}

      Mox.expect(MockStore, :list, fn _schema, _fields, _values ->
        raise "the store is unreachable"
      end)

      loader =
        loader
        |> Dataloader.load(:garage, :cars, customer)
        |> Dataloader.run()

      assert {:error, {%RuntimeError{message: "the store is unreachable"}, _stacktrace}} =
               Dataloader.get(loader, :garage, :cars, customer)
    end

    test "returns an error for a record of a batch that raised when async is false" do
      customer = %Garage.Customer{id: 1, name: "John"}
      source = Associations.Dataloader.new(Garage, async: false)
      loader = Dataloader.add_source(Dataloader.new(get_policy: :tuples), :garage, source)

      Mox.expect(MockStore, :list, fn _schema, _fields, _values ->
        raise "the store is unreachable"
      end)

      loader =
        loader
        |> Dataloader.load(:garage, :cars, customer)
        |> Dataloader.run()

      assert {:error, %RuntimeError{message: "the store is unreachable"}} =
               Dataloader.get(loader, :garage, :cars, customer)
    end

    @tag :capture_log
    test "returns an error for a single association finding more than one record",
         %{loader: loader} do
      car = %Garage.Car{id: 1, color: "red", owner_id: 1, dealer_code: "AAA"}

      Mox.expect(MockStore, :list, fn Garage.Customer, [:id], [[1]] ->
        [%Garage.Customer{id: 1, name: "John"}, %Garage.Customer{id: 1, name: "Twin"}]
      end)

      loader =
        loader
        |> Dataloader.load(:garage, :owner, car)
        |> Dataloader.run()

      assert {:error, {%RuntimeError{message: message}, _stacktrace}} =
               Dataloader.get(loader, :garage, :owner, car)

      assert message == "the :owner association of Garage.Car found 2 records"
    end

    test "returns an error for a record that was not loaded", %{loader: loader} do
      customer = %Garage.Customer{id: 1, name: "John"}
      other = %Garage.Customer{id: 2, name: "Jane"}

      loader =
        loader
        |> Dataloader.load(:garage, :cars, customer)
        |> Dataloader.run()

      assert Dataloader.get(loader, :garage, :cars, other) ==
               {:error, "Unable to find item #{inspect(other)} in batch"}
    end

    test "returns an error for a batch that was not loaded", %{loader: loader} do
      customer = %Garage.Customer{id: 1, name: "John"}

      assert Dataloader.get(loader, :garage, :cars, customer) ==
               {:error, "Unable to find batch :cars"}
    end
  end

  describe "options" do
    test "fetches in the process calling run when async is false", %{test_pid: caller} do
      source = Associations.Dataloader.new(Garage, async: false)
      loader = Dataloader.add_source(Dataloader.new(), :garage, source)

      Mox.expect(MockStore, :list, fn _schema, _fields, _values ->
        assert self() == caller

        []
      end)

      loader
      |> Dataloader.load(:garage, :cars, %Garage.Customer{id: 1, name: "John"})
      |> Dataloader.run()
    end

    test "fetches in another process when async is true", %{loader: loader, test_pid: caller} do
      Mox.expect(MockStore, :list, fn _schema, _fields, _values ->
        refute self() == caller

        []
      end)

      loader
      |> Dataloader.load(:garage, :cars, %Garage.Customer{id: 1, name: "John"})
      |> Dataloader.run()
    end

    test "rejects an unknown option" do
      assert_raise ArgumentError, ~r/unknown keys \[:unknown\]/, fn ->
        Associations.Dataloader.new(Garage, unknown: true)
      end
    end
  end
end
