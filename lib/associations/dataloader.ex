if Code.ensure_loaded?(Dataloader.Source) do
  defmodule Associations.Dataloader do
    @moduledoc """
    A `Dataloader.Source` that loads associations through a module that `use`s `Associations`.

    The batch key is an association name, and the item is the record it is loaded for. Every
    record queued under the same name is loaded in one `load/3` call when the loader runs,
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

    The batch key may also be a `{name, args}` pair, and `args` are then passed to `load/3` as
    its `:args`, so each record is listed with them in a call of its own. A map is turned into a
    keyword list sorted by key, so the same args given as a map or as a keyword list share a batch.

        Dataloader.load(loader, :garage, {:cars, %{color: "red"}}, customer)

    Requires the `:dataloader` dependency. This module is not compiled without it.
    """

    defstruct [:module, :async, :timeout, batches: %{}, results: %{}]

    @opaque t :: %__MODULE__{
              module: module,
              async: boolean,
              timeout: timeout,
              batches: %{optional({atom, keyword}) => MapSet.t(struct)},
              results: %{
                optional({atom, keyword}) => %{optional(struct) => {:ok, term} | {:error, term}}
              }
            }

    @doc """
    Builds a source loading the associations `module` declares.

    ## Options

      * `:async` - whether the batches of the source run concurrently, each in its own task, and
        whether the searches inside a batch do, as `:async` of `load/3`. Defaults to `true`.
        Pass `false` where `c:Associations.list/4` has to run in the process calling
        `Dataloader.run/1`, such as inside an `Ecto.Repo` transaction.

      * `:timeout` - the time, in milliseconds, a batch may take before the whole source fails.
        Defaults to `Dataloader.default_timeout/0`.
    """
    @spec new(module, async: boolean, timeout: timeout) :: t
    def new(module, opts \\ []) when is_atom(module) and is_list(opts) do
      opts = Keyword.validate!(opts, async: true, timeout: Dataloader.default_timeout())

      %__MODULE__{
        module: module,
        async: Keyword.fetch!(opts, :async),
        timeout: Keyword.fetch!(opts, :timeout)
      }
    end

    defimpl Dataloader.Source do
      def load(source, batch_key, item) do
        key = normalize_key(batch_key)

        case source.results do
          %{^key => %{^item => {:ok, _result}}} ->
            source

          _results ->
            batches = Map.update(source.batches, key, MapSet.new([item]), &MapSet.put(&1, item))
            %{source | batches: batches}
        end
      end

      def put(source, batch_key, item, result) do
        key = normalize_key(batch_key)

        results =
          Map.update(
            source.results,
            key,
            %{item => {:ok, result}},
            &Map.put(&1, item, {:ok, result})
          )

        %{source | results: results}
      end

      def fetch(source, batch_key, item) do
        key = normalize_key(batch_key)

        case source.results do
          %{^key => %{^item => result}} -> result
          %{^key => _batch} -> {:error, "Unable to find item #{inspect(item)} in batch"}
          _results -> {:error, "Unable to find batch #{inspect(batch_key)}"}
        end
      end

      def run(source) do
        outcomes =
          if source.async do
            Dataloader.async_safely(Dataloader, :run_tasks, [
              source.batches,
              &load_batch(source, &1),
              [timeout: source.timeout]
            ])
          else
            Map.new(source.batches, fn batch ->
              try do
                {batch, {:ok, load_batch(source, batch)}}
              rescue
                exception -> {batch, {:error, exception}}
              end
            end)
          end

        results =
          Enum.reduce(outcomes, source.results, fn
            {{key, _items}, {:ok, loaded}}, results ->
              Map.update(results, key, loaded, &Map.merge(&1, loaded))

            {{key, items}, {:error, reason}}, results ->
              failed = Map.new(items, &{&1, {:error, reason}})
              Map.update(results, key, failed, &Map.merge(&1, failed))
          end)

        %{source | batches: %{}, results: results}
      end

      def pending_batches?(source), do: source.batches != %{}

      def timeout(source), do: source.timeout

      def async?(source), do: source.async

      defp load_batch(source, {{name, args}, items}) do
        items = MapSet.to_list(items)
        results = source.module.load(items, name, args: args, async: source.async)

        Map.new(Enum.zip(items, results), fn {item, result} -> {item, {:ok, result}} end)
      end

      defp normalize_key({name, args})
           when is_atom(name) and not is_nil(name) and (is_map(args) or is_list(args)) do
        {name, args |> Enum.to_list() |> Enum.sort_by(&elem(&1, 0))}
      end

      defp normalize_key(name) when is_atom(name) and not is_nil(name), do: {name, []}

      defp normalize_key(batch_key) do
        raise ArgumentError,
              "expected an association name or a {name, args} pair as the batch key, " <>
                "got: #{inspect(batch_key)}"
      end
    end
  end
end
