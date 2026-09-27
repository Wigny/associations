if Code.ensure_loaded?(Dataloader.Source) do
  defmodule Associations.Dataloader do
    @moduledoc """
    A `Dataloader.Source` that loads associations through a module that `use`s `Associations`.

    The batch key is an association name, and the item is the record it is loaded for. Every
    record queued under the same name is loaded in one `load_many/3` call when the loader runs,
    whatever its schema.

        loader =
          Dataloader.new()
          |> Dataloader.add_source(:garage, Associations.Dataloader.new(Garage))
          |> Dataloader.load(:garage, :cars, customer)
          |> Dataloader.load(:garage, :owner, car)
          |> Dataloader.run()

        iex> Dataloader.get(loader, :garage, :cars, customer)
        [%Garage.Car{id: 1}, %Garage.Car{id: 2}]

        iex> Dataloader.get(loader, :garage, :owner, car)
        %Garage.Customer{id: 1}

    A `belongs_to` or a `has_one` answers with a single record, or `nil`, and a `has_many` with a
    list, the way `load/3` does.

    The batch key may also be a `{name, args}` pair, and `args` are then passed to `load_many/3` as
    its `:args`, so each record is listed with them in a call of its own. A map is turned into a
    keyword list sorted by key, so the same args given as a map or as a keyword list share a batch.

        Dataloader.load(loader, :garage, {:cars, %{color: "red"}}, customer)

    Requires the `:dataloader` dependency. This module is not compiled without it.
    """

    alias Associations.Resolver

    defstruct [:module, :opts, batches: %{}, results: %{}]

    @opaque t :: %__MODULE__{
              module: module,
              opts: [async: boolean, timeout: timeout],
              batches: %{optional(term) => MapSet.t(struct)},
              results: %{optional(term) => %{optional(struct) => {:ok, term} | {:error, term}}}
            }

    @doc """
    Builds a source loading the associations `module` declares.

    ## Options

      * `:async` - whether the batches of the source run concurrently, each in its own task, and
        whether the searches inside a batch do, as `:async` of `load_many/3`. Defaults to `true`.
        Pass `false` where `c:Associations.list/4` has to run in the process calling
        `Dataloader.run/1`, such as inside an `Ecto.Repo` transaction.

      * `:timeout` - the time, in milliseconds, a batch may take before the whole source fails.
        Defaults to `30000`.
    """
    @spec new(module, async: boolean, timeout: timeout) :: t
    def new(module, opts \\ []) when is_atom(module) and is_list(opts) do
      opts = Keyword.validate!(opts, async: true, timeout: to_timeout(second: 30))

      %__MODULE__{module: module, opts: opts}
    end

    defimpl Dataloader.Source do
      def load(source, batch_key, item) do
        batch_key = normalize_key(batch_key)

        if fetched?(source.results, batch_key, item) do
          source
        else
          update_in(source.batches, fn batches ->
            Map.update(batches, batch_key, MapSet.new([item]), &MapSet.put(&1, item))
          end)
        end
      end

      def put(source, batch_key, item, result) do
        batch_key = normalize_key(batch_key)

        results =
          Map.update(source.results, batch_key, {:ok, %{item => result}}, fn
            {:ok, batch} -> {:ok, Map.put(batch, item, result)}
            {:error, _reason} -> {:ok, %{item => result}}
          end)

        %{source | results: results}
      end

      def fetch(source, batch_key, item) do
        batch_key = normalize_key(batch_key)

        case Map.fetch(source.results, batch_key) do
          {:ok, batch} -> fetch_item(batch, item)
          :error -> {:error, "Unable to find batch #{inspect(batch_key)}"}
        end
      end

      def run(source) do
        results =
          Dataloader.async_safely(__MODULE__, :run_batches, [source],
            async?: Dataloader.Source.async?(source)
          )

        results =
          Map.merge(source.results, results, fn
            _batch_key, {:ok, batch}, {:ok, new_batch} -> {:ok, Map.merge(batch, new_batch)}
            _batch_key, _batch, new_batch -> new_batch
          end)

        %{source | batches: %{}, results: results}
      end

      def pending_batches?(source), do: source.batches != %{}

      def timeout(source), do: source.opts[:timeout]

      def async?(source), do: source.opts[:async]

      def run_batches(source) do
        batches = Enum.to_list(source.batches)
        options = [timeout: source.opts[:timeout], on_timeout: :kill_task]

        results =
          batches
          |> run_stream(&run_batch(source, &1), options, async?(source))
          |> Enum.map(fn
            {:ok, result} -> {:ok, result}
            {:exit, reason} -> {:error, reason}
          end)

        batches
        |> Enum.map(fn {batch_key, _items} -> batch_key end)
        |> Enum.zip(results)
        |> Map.new()
      end

      defp run_stream(batches, fun, options, true) do
        Dataloader.async_stream(batches, fun, options)
      end

      defp run_stream(batches, fun, _options, _async?) do
        Enum.map(batches, fn batch ->
          try do
            {:ok, fun.(batch)}
          rescue
            exception -> {:exit, exception}
          end
        end)
      end

      defp run_batch(source, {{name, args}, items}), do: run_batch(source, name, args, items)
      defp run_batch(source, {name, items}), do: run_batch(source, name, [], items)

      defp run_batch(%{module: module} = source, name, args, items) do
        items
        |> MapSet.to_list()
        |> module.load_many(name, async: source.opts[:async], args: args)
        |> Map.new(fn {item, records} -> {item, Resolver.shape(module, item, name, records)} end)
      end

      defp fetch_item({:error, _reason} = error, _item), do: error

      defp fetch_item({:ok, batch}, item) do
        case Map.fetch(batch, item) do
          {:ok, result} -> {:ok, result}
          :error -> {:error, "Unable to find item #{inspect(item)} in batch"}
        end
      end

      defp fetched?(results, batch_key, item) do
        match?(%{^batch_key => {:ok, %{^item => _result}}}, results)
      end

      defp normalize_key({name, args}) when args == %{} or args == [] do
        normalize_key(name)
      end

      defp normalize_key({name, args}) when is_atom(name) and (is_map(args) or is_list(args)) do
        {name, Enum.sort(args)}
      end

      defp normalize_key(name) when is_atom(name) and not is_nil(name), do: name

      defp normalize_key(batch_key) do
        raise ArgumentError,
              "expected an association name or a {name, args} pair as the batch key, " <>
                "got: #{inspect(batch_key)}"
      end
    end
  end
end
