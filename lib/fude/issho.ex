if Code.ensure_loaded?(Issho.State) do
  defmodule Fude.Issho do
    @moduledoc ~S"""
    Collaboration on charts, for people and agents, in
    [Issho](https://hex.pm/packages/issho)'s rooms: a chart's spec is a
    shared state of the room (`Issho.State`), that everyone changes with
    the same functions, and that is a valid chart after every change.

    Fude draws charts on its own; this module is only for a chart that
    others change too: a report two people build at once, a chart an agent
    makes beside you. It is compiled when Issho is in your deps.

    ## The document

    A shared chart is a document of a room. Define it in your policy, from
    the chart your app keeps, and save it in `:on_change`:

        def document(_who, "report:" <> id = doc) do
          report = Reports.get!(id)
          Fude.Issho.document(report.chart, on_change: &Reports.save_chart(report, &1, &2))
        end

    `Fude.Issho.document/2` gives Issho the chart's spec, with an id for
    each layer and annotation (so that two changes to two layers at once
    both stay), and a hook that refuses a change that would make the chart
    invalid: the person or the agent who made it gets every error, with
    where it is. `:on_change` gets the chart after each change and who made
    it, and answers `:ok` or `{:error, reason}` to refuse it.

    ## In a LiveView

        def mount(%{"id" => id}, _session, socket) do
          room = "report:" <> id
          report = Reports.get!(id)

          if connected?(socket),
            do: {:ok, _} = Issho.Live.join(MyApp.Issho, socket.assigns.current_user, room)

          {:ok, Fude.Issho.assign(socket, :chart, room, room, report.chart)}
        end

        def handle_event("title", %{"title" => title}, socket) do
          :ok = Fude.Issho.change(socket, :chart, &Fude.title(&1, title))
          {:noreply, socket}
        end

    ```heex
    <.chart id="revenue" spec={@chart} data={@sales} issho="report:7" />
    ```

    `@chart` is the chart's spec, and changes as anyone changes it.
    `change/3` takes a function of the chart, made with `Fude`'s own
    functions (`Fude.title/3`, `Fude.annotate/3`, `Fude.layers/3`), and
    sends only what it changed. The `issho` attribute of `<.chart>` is the
    chart's document: the people in the room see each other's pointers on
    its marks, at the same data on every screen (`Fude.Issho.Place`).

    ## Agents

    An agent uses the same chart: `tools/0` gives `read_chart`, which says
    what a chart shows (its spec, and the table of its data when your app
    gives it), and `change_chart`, which takes the spec as the agent wants
    it and sends what changed. Issho's `point` tool points at a mark, in
    `Fude.Issho.Place`'s terms, and its `update_state` changes a spec by
    paths too. Every change passes the same hook as a person's.

    The data of a chart is your app's, read as the agent:

        config :fude, Fude.Issho, data: {MyApp.Reports, :chart_data}

        def chart_data("report:" <> id, ctx), do: {:ok, Reports.sales(id, ctx.opts[:on_behalf_of])}
    """

    use Issho.Binding, engine: Issho.Engine.Map, place: Fude.Issho.Place

    alias Fude.{Chart, Spec}

    @lists ~w(layers annotations)

    @doc """
    A shared chart's document, for your policy's `document/2`: the chart
    (a `Fude.Chart`, or a spec) as the room's shared state, refused when a
    change makes it invalid.

    Options: `:on_change`, a function of the chart after a change and the
    transaction's context (`:by`, `:document`, `:revision`), answering
    `:ok` or `{:error, reason}`; `:store`, Issho's store of the document
    (the instance's unless given).
    """
    @spec document(Chart.t() | Spec.t(), keyword()) :: {:ok, map()} | {:error, term()}
    def document(chart_or_spec, opts \\ []) do
      with {:ok, chart} <- chart(chart_or_spec) do
        {:ok,
         %{engine: __MODULE__, initial: state(chart), on_transaction: hook(opts[:on_change])}
         |> put_store(opts)}
      end
    end

    defp put_store(spec, opts) do
      case Keyword.fetch(opts, :store) do
        {:ok, store} -> Map.put(spec, :store, store)
        :error -> spec
      end
    end

    @doc """
    The chart as a shared state: its spec (`Fude.Spec.dump/2`), with its
    layers in `"layers"` and an id for each layer and annotation that has
    none.
    """
    @spec state(Chart.t()) :: Spec.t()
    def state(%Chart{} = chart) do
      layers = Enum.map(chart.layers, &%{&1 | id: &1.id || id("l")})
      annotations = Enum.map(chart.annotations, &%{&1 | id: &1.id || id("n")})
      Spec.dump(%{chart | layers: layers, annotations: annotations}, layers: true)
    end

    # A new id, unique enough that two people who add a layer at once do
    # not pick the same.
    defp id(prefix),
      do: prefix <> (6 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false))

    @doc "The chart of a shared state (or of a chart, as it is), or the errors of it in words."
    @spec chart(Chart.t() | Spec.t()) :: {:ok, Chart.t()} | {:error, String.t()}
    def chart(%Chart{} = chart), do: {:ok, chart}

    def chart(state) when is_map(state) do
      case Spec.load(state) do
        {:ok, chart} -> {:ok, chart}
        {:error, errors} -> {:error, "the chart is not valid:\n" <> errors(errors, state)}
      end
    end

    @doc false
    # The errors of a spec in words, a layer or an annotation by its id.
    @spec errors([Spec.error()], Spec.t()) :: String.t()
    def errors(errors, state) do
      errors
      |> Enum.map(fn
        %{path: [list, index | rest]} = error when list in @lists and is_integer(index) ->
          %{error | path: [list, item_id(state, list, index) | rest]}

        error ->
          error
      end)
      |> Spec.format_errors()
    end

    defp item_id(state, list, index) do
      case state |> Map.get(list, []) |> Enum.at(index) do
        %{"id" => id} when is_binary(id) -> id
        _other -> index
      end
    end

    defp hook(on_change) do
      fn _ops, %{after: state} = context ->
        with {:ok, chart} <- chart(state), do: changed(on_change, chart, context)
      end
    end

    defp changed(nil, _chart, _context), do: :ok

    defp changed(on_change, chart, context) do
      case on_change.(chart, context) do
        {:error, reason} -> {:error, reason}
        _ok -> :ok
      end
    end

    @doc ~S"""
    The operations (`Issho.State`) that make one shared state into
    another: a `set` or a `delete` for each key that changed, and, for the
    layers and annotations, an `insert`, a `move` or a `remove` of each by
    its id, and a `set` of each key of one that changed. Two people who
    change two keys, or two layers, at once both have their change.

        iex> Fude.Issho.ops(%{"title" => "Q3"}, %{"title" => "Q4"})
        [%{"op" => "set", "path" => ["title"], "value" => "Q4"}]
    """
    @spec ops(Spec.t(), Spec.t()) :: [map()]
    def ops(old, new) when is_map(old) and is_map(new) do
      (Map.keys(old) ++ Map.keys(new))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.flat_map(&key_ops([&1], Map.fetch(old, &1), Map.fetch(new, &1)))
    end

    defp key_ops(path, {:ok, _old}, :error), do: [Issho.State.delete(path)]
    defp key_ops(_path, same, same), do: []

    defp key_ops([key] = path, {:ok, old}, {:ok, new}) when key in @lists do
      if items?(old) and items?(new),
        do: list_ops(path, old, new),
        else: [Issho.State.set(path, new)]
    end

    defp key_ops(path, _old, {:ok, new}), do: [Issho.State.set(path, new)]

    defp items?(list),
      do: is_list(list) and Enum.all?(list, &match?(%{"id" => id} when is_binary(id), &1))

    # The items of a list by their ids: those gone are removed, and each of
    # the others, in the new order, is inserted or moved after the one
    # before it, when it is not there yet, and then changed key by key.
    defp list_ops(path, old, new) do
      olds = Map.new(old, &{&1["id"], &1})
      ids = Enum.map(new, & &1["id"])
      removed = Enum.map(old, & &1["id"]) -- ids

      {ops, _order} =
        new
        |> Enum.with_index()
        |> Enum.reduce({[], Enum.map(old, & &1["id"]) -- removed}, fn {item, index},
                                                                      {ops, order} ->
          id = item["id"]
          prev = if index > 0, do: Enum.at(ids, index - 1)
          {more, order} = item_ops(path, item, olds[id], prev, order)
          {ops ++ more, order}
        end)

      Enum.map(removed, &Issho.State.remove(path, &1)) ++ ops
    end

    defp item_ops(path, item, nil, prev, order),
      do: {[Issho.State.insert(path, item, where(prev))], place(order, item["id"], prev)}

    defp item_ops(path, item, old, prev, order) do
      id = item["id"]
      changes = Enum.reject(ops(old, item), &(&1["path"] == ["id"]))
      changes = Enum.map(changes, &Map.update!(&1, "path", fn keys -> path ++ [id | keys] end))

      if after?(order, id, prev),
        do: {changes, order},
        else: {[Issho.State.move(path, id, where(prev)) | changes], place(order, id, prev)}
    end

    defp where(nil), do: [at: :start]
    defp where(prev), do: [after: prev]

    defp after?(order, id, nil), do: List.first(order) == id

    defp after?(order, id, prev),
      do: Enum.at(order, Enum.find_index(order, &(&1 == prev)) + 1) == id

    defp place(order, id, nil), do: [id | List.delete(order, id)]

    defp place(order, id, prev) do
      order = List.delete(order, id)
      List.insert_at(order, Enum.find_index(order, &(&1 == prev)) + 1, id)
    end

    @doc "Fude's tools for agents: `read_chart` and `change_chart`."
    @spec tools() :: [module()]
    def tools, do: [Fude.Issho.Tools.Read, Fude.Issho.Tools.Change]

    @doc false
    # The data of a shared chart, for the agent of a context, from the
    # app's `config :fude, Fude.Issho, data: {module, function}`.
    @spec data(String.t(), term()) :: {:ok, term()} | :none | {:error, String.t()}
    def data(document, ctx) do
      case Keyword.get(Application.get_env(:fude, __MODULE__, []), :data) do
        nil -> :none
        {module, function} -> module |> Kernel.apply(function, [document, ctx]) |> data_result()
        function when is_function(function, 2) -> document |> function.(ctx) |> data_result()
      end
    end

    defp data_result({:ok, data}), do: {:ok, data}
    defp data_result({:error, reason}), do: {:error, to_string(reason)}
    defp data_result(nil), do: :none

    if Code.ensure_loaded?(Phoenix.LiveView) do
      alias Phoenix.LiveView.Socket

      @doc """
      Assigns a shared chart's spec as `key`, kept up to date as anyone
      changes it (`Issho.State.assign/5`). Before the LiveView is in the
      room (the static render), it is the spec of `chart`.
      """
      @spec assign(Socket.t(), atom(), String.t(), String.t(), Chart.t() | Spec.t()) :: Socket.t()
      def assign(socket, key, room, document, chart) do
        {:ok, chart} = chart(chart)
        Issho.State.assign(socket, key, room, document, default: state(chart))
      end

      @doc """
      Changes the shared chart assigned as `key` with a function of the
      chart (`Fude`'s functions), and sends what changed, as one change.
      Gives `:ok`, or `{:error, reason}`: the chart it makes is not valid,
      or the room refused it.
      """
      @spec change(Socket.t(), atom(), (Chart.t() -> Chart.t())) :: :ok | {:error, term()}
      def change(%Socket{} = socket, key, fun) when is_function(fun, 1) do
        state = socket.assigns[key]

        with {:ok, chart} <- chart(state),
             new = state(fun.(chart)),
             {:ok, _valid} <- chart(new) do
          case ops(state, new) do
            [] -> :ok
            ops -> Issho.State.change(socket, key, ops)
          end
        end
      end
    end
  end
end
