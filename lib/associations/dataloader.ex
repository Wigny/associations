if Code.ensure_loaded?(Dataloader.Source) do
  defmodule Associations.Dataloader do
    @moduledoc """
    A `Dataloader.Source` that loads associations through a module that `use`s `Associations`.

    The batch key is an association path, one name or a list of them, and the item is the record
    it is loaded for. Every record queued under the same path is loaded in one `load_many/3`
    call when the loader runs, whatever its schema.

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

    A path made only of `belongs_to` and `has_one` associations answers with a single record, or
    `nil`, the way `load/3` does. Any `has_many` along it makes the answer a list.

    Requires the `:dataloader` dependency. This module is not compiled without it.
    """

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
        whether the fetches inside a batch do, as `:async` of `load_many/3`. Defaults to `true`.
        Pass `false` where `c:Associations.fetch/3` has to run in the process calling
        `Dataloader.run/1`, such as inside an `Ecto.Repo` transaction.

      * `:timeout` - the time, in milliseconds, a batch may take before the whole source fails.
        Defaults to `30000`.
    """
    @spec new(module, async: boolean, timeout: timeout) :: t
    def new(module, opts \\ []) when is_atom(module) and is_list(opts) do
      opts = Keyword.validate!(opts, async: true, timeout: to_timeout(second: 30))

      %__MODULE__{module: module, opts: opts}
    end

    @doc false
    def path!(path) when is_atom(path) or is_list(path), do: path
    def path!({path, args}) when is_map(args) and map_size(args) == 0, do: path!(path)

    def path!({path, args}) when is_map(args) do
      raise ArgumentError,
            "#{inspect(__MODULE__)} cannot apply the arguments #{inspect(args)} to the " <>
              "#{inspect(path)} association"
    end

    def path!(batch_key) do
      raise ArgumentError,
            "expected an association path or a {path, args} pair as the batch key, got: " <>
              inspect(batch_key)
    end

    @doc false
    def loaded?(%__MODULE__{results: results}, batch_key, record) do
      match?(%{^batch_key => %{^record => {:ok, _result}}}, results)
    end

    @doc false
    def enqueue(%__MODULE__{batches: batches} = source, batch_key, record) do
      batches = Map.update(batches, batch_key, MapSet.new([record]), &MapSet.put(&1, record))

      %{source | batches: batches}
    end

    @doc false
    def run_batches(%__MODULE__{batches: batches, opts: opts} = source) do
      opts = [timeout: opts[:timeout], async?: opts[:async]]

      Dataloader.async_safely(
        Dataloader,
        :run_tasks,
        [batches, &load_batch(source, &1), opts],
        opts
      )
    end

    defp load_batch(%__MODULE__{module: module, opts: opts}, {batch_key, records}) do
      path = path!(batch_key)

      records
      |> MapSet.to_list()
      |> module.load_many(path, opts)
      |> Map.new(&shape(module, path, &1))
    end

    defp shape(module, path, {%schema{} = record, records}) do
      if one?(module, schema, path) do
        {record, {:ok, one!(records, schema, path)}}
      else
        {record, {:ok, records}}
      end
    end

    @doc false
    def store(%__MODULE__{batches: batches} = source, {:exit, exception}) do
      store(source, Map.new(batches, &{&1, {:error, exception}}))
    end

    def store(%__MODULE__{} = source, batch_results) do
      Enum.reduce(batch_results, %{source | batches: %{}}, &store_batch(&2, &1))
    end

    defp store_batch(source, {{batch_key, _records}, {:ok, results}}) do
      put_results(source, batch_key, results)
    end

    defp store_batch(source, {{batch_key, records}, {:error, reason}}) do
      put_results(source, batch_key, Map.new(records, &{&1, {:error, reason}}))
    end

    @doc false
    def put_results(%__MODULE__{results: results} = source, batch_key, batch) do
      %{source | results: Map.update(results, batch_key, batch, &Map.merge(&1, batch))}
    end

    @doc false
    def fetch_result(%__MODULE__{results: results}, batch_key, record) do
      case results do
        %{^batch_key => %{^record => result}} -> result
        %{^batch_key => _batch} -> {:error, "Unable to find item #{inspect(record)} in batch"}
        _results -> {:error, "Unable to find batch #{inspect(batch_key)}"}
      end
    end

    defp one?(module, schema, path) do
      Enum.all?(kinds(module, schema, path), &(&1 in [:belongs_to, :has_one]))
    end

    defp kinds(module, schema, path) do
      {kinds, _schema} = Enum.map_reduce(List.wrap(path), schema, &hop(module, &2, &1))

      kinds
    end

    defp hop(module, schema, name) do
      {kind, %{target: target}} = Map.fetch!(module.__definitions__(), {schema, name})

      {kind, target}
    end

    defp one!([], _schema, _path), do: nil
    defp one!([record], _schema, _path), do: record

    defp one!(records, schema, path) do
      raise "the #{inspect(path)} association of #{inspect(schema)} found #{length(records)} records"
    end

    defimpl Dataloader.Source do
      def load(source, batch_key, record) do
        @for.path!(batch_key)

        if @for.loaded?(source, batch_key, record) do
          source
        else
          @for.enqueue(source, batch_key, record)
        end
      end

      def run(source), do: @for.store(source, @for.run_batches(source))

      def fetch(source, batch_key, record), do: @for.fetch_result(source, batch_key, record)

      def put(source, batch_key, record, result) do
        @for.put_results(source, batch_key, %{record => {:ok, result}})
      end

      def pending_batches?(source), do: map_size(source.batches) > 0

      def timeout(source), do: source.opts[:timeout]

      def async?(source), do: source.opts[:async]
    end
  end
end
