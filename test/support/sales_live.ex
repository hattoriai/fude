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

  def handle_event("more", _params, socket) do
    {:noreply, update(socket, :sales, &[%{region: "East", channel: "Online", revenue: 40} | &1])}
  end
end
