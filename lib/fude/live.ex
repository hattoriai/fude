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
  Has the browser save the chart of an id as a file: `:svg`, or `:png`
  at twice its size. The file has the chart's title, legend and source,
  as on the page.
  """
  @spec export(Phoenix.LiveView.Socket.t(), String.t(), :svg | :png) ::
          Phoenix.LiveView.Socket.t()
  def export(socket, id, format) when format in [:svg, :png],
    do: Phoenix.LiveView.push_event(socket, "fude:export", %{id: id, format: format})

  @doc """
  The range of a brush (`brush: :select`), from the params of the
  `"fude:brush"` event a chart sends when a person drags across its x
  axis: `{from, to}`, both included, in the axis's terms. A date for a
  time of a day or more (a time with a unit snaps to whole units: the
  first and the last of them), a `DateTime` for a time of a day, or a
  number.

      def handle_event("fude:brush", %{"id" => "orders"} = params, socket) do
        {from, to} = Fude.Live.brush_range(params)
        {:noreply, assign(socket, period: {from, to})}
      end

  Raises an `ArgumentError` for params that are not a brush's.
  """
  @spec brush_range(map()) :: {term(), term()}
  def brush_range(%{"from" => from, "to" => to}), do: {brush_value(from), brush_value(to)}

  def brush_range(params),
    do: raise(ArgumentError, "Fude.Live.brush_range/1: not a brush's params: #{inspect(params)}")

  defp brush_value(value) when is_number(value), do: value

  defp brush_value(value) when is_binary(value) do
    with {:error, _} <- Date.from_iso8601(value),
         {:error, _} <- datetime(value) do
      raise ArgumentError,
            "Fude.Live.brush_range/1: not a date, a time or a number: #{inspect(value)}"
    else
      {:ok, value} -> value
    end
  end

  defp brush_value(value),
    do:
      raise(
        ArgumentError,
        "Fude.Live.brush_range/1: not a date, a time or a number: #{inspect(value)}"
      )

  defp datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> {:ok, time}
      {:error, _} = error -> error
    end
  end

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
        Phoenix.LiveView.push_event(socket, "fude:append", %{
          id: id,
          wire: Fude.Wire.pack(wire),
          max: opts[:max]
        })

      {:error, errors} ->
        raise ArgumentError,
              "Fude.Live.append/5: the rows do not fit the chart: " <> Enum.join(errors, "; ")
    end
  end
end
