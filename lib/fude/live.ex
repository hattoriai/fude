defmodule Fude.Live do
  @moduledoc """
  New points for a chart on the page, without sending its data again.

  A chart follows its assigns: when the data of `<.chart>` changes, the
  chart draws again in place, its marks moving to their new places. For a
  chart that grows a point at a time (a reading every second, the orders
  of the day), `append/5` sends only the new rows: the chart takes them in,
  keeps the last `max` of them, and moves.

      def mount(_params, _session, socket) do
        if connected?(socket), do: Phoenix.PubSub.subscribe(MyApp.PubSub, "readings")
        {:ok, assign(socket, chart: Fude.line(x: :at, y: :load), readings: Readings.last(60))}
      end

      def handle_info({:reading, reading}, socket) do
        {:noreply, Fude.Live.append(socket, "load", socket.assigns.chart, [reading], max: 60)}
      end

      <.chart id="load" chart={@chart} data={@readings} />

  The new rows go through the chart's rules as its data does (types, units
  of time, formats), and are added to its marks: a chart whose marks are
  its rows (lines, areas and points with no aggregate). A chart that sums
  or counts its rows draws again from its assigns instead.

  The page's table of the data is the one of the last render.
  """

  alias Fude.{Chart, Compile}

  @doc """
  Sends new rows to the chart of an id, made with the chart they belong to
  (without its data). Options:

    * `:max` - the most rows the chart keeps: the oldest go first. All of
      them when not given.
  """
  @spec append(Phoenix.LiveView.Socket.t(), String.t(), Chart.t(), list() | map(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def append(socket, id, %Chart{} = chart, rows, opts \\ []) do
    case Compile.compile(%{chart | datasets: %{}}, %{chart.data => rows}) do
      {:ok, wire} ->
        Phoenix.LiveView.push_event(socket, "fude:append", %{id: id, wire: wire, max: opts[:max]})

      {:error, errors} ->
        raise ArgumentError,
              "Fude.Live.append/5: the rows do not fit the chart: " <> Enum.join(errors, "; ")
    end
  end
end
