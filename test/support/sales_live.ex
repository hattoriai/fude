defmodule FudeTest.SalesLive do
  @moduledoc "A LiveView with a chart of sales, for the tests of Fude.Components and Fude.Test."
  use Phoenix.LiveView

  import Fude.Components

  @sales [
    %{region: "North", channel: "Online", revenue: 120},
    %{region: "North", channel: "Retail", revenue: 80},
    %{region: "South", channel: "Online", revenue: 60},
    %{region: "South", channel: "Retail", revenue: 90}
  ]

  def mount(_params, _session, socket), do: {:ok, assign(socket, sales: @sales)}

  def render(assigns) do
    ~H"""
    <.chart id="revenue" chart={Fude.bar(@sales, x: :region, y: :revenue, color: :channel, title: "Revenue")} />
    <button phx-click="more">More</button>
    """
  end

  def handle_event("stream", _params, socket) do
    chart = Fude.bar(x: :region, y: :revenue, color: :channel)
    row = %{region: "West", channel: "Online", revenue: 10}
    {:noreply, Fude.Live.append(socket, "revenue", chart, [row], max: 50)}
  end

  # Rows enough that their days are sent packed.
  def handle_event("stream_days", _params, socket) do
    chart = Fude.line(x: :day, y: :revenue)
    rows = for d <- 0..199, do: %{day: Date.add(~D[2026-01-01], d), revenue: d * 2}
    {:noreply, Fude.Live.append(socket, "revenue", chart, rows)}
  end

  def handle_event("more", _params, socket) do
    {:noreply, update(socket, :sales, &[%{region: "East", channel: "Online", revenue: 40} | &1])}
  end
end
