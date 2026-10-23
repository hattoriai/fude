defmodule FudeTest.Reports do
  @moduledoc "The app's side of the shared charts of the tests: a chart, its data, and where it is saved."

  @sales [
    %{region: "North", channel: "Online", revenue: 120},
    %{region: "North", channel: "Retail", revenue: 80},
    %{region: "South", channel: "Online", revenue: 60},
    %{region: "South", channel: "Retail", revenue: 90}
  ]

  def sales, do: @sales

  def chart, do: Fude.bar(x: :region, y: {:sum, :revenue}, color: :channel, title: "Revenue")

  # The data an agent reads, as the app gives it (config :fude, Fude.Issho).
  def data("report:" <> _id, _ctx), do: {:ok, @sales}
  def data(_document, _ctx), do: {:error, "no such report"}

  # Each change, to the test that opened the room (named in it).
  def saved(room) do
    fn chart, context ->
      case Process.whereis(owner(room)) do
        nil -> :ok
        pid -> send(pid, {:saved, chart, context[:by]})
      end

      :ok
    end
  end

  def owner("report:" <> id), do: String.to_atom("fude_test_report_" <> id)
end

defmodule FudeTest.Policy do
  @moduledoc false
  @behaviour Issho.Policy

  @impl true
  def authorize(_identity, _room, _action), do: :ok

  @impl true
  def document(_identity, "report:" <> _ = room),
    do:
      Fude.Issho.document(FudeTest.Reports.chart(),
        on_change: FudeTest.Reports.saved(room),
        store: :none
      )

  def document(_identity, _id), do: {:error, :not_found}
end

defmodule FudeTest.SharedLive do
  @moduledoc "A LiveView with a shared chart (Fude.Issho), for its tests."
  use Phoenix.LiveView

  import Fude.Components

  on_mount(Issho.Live)

  def mount(_params, %{"room" => room, "user" => user}, socket) do
    if connected?(socket),
      do: {:ok, _} = Issho.Live.join(FudeTest.Issho, %{id: user, name: user}, room)

    {:ok,
     socket
     |> assign(room: room, sales: FudeTest.Reports.sales())
     |> Fude.Issho.assign(:chart, room, room, FudeTest.Reports.chart())}
  end

  def render(assigns) do
    ~H"""
    <.chart id="revenue" spec={@chart} data={@sales} issho={@room} />
    """
  end

  def handle_event("title", %{"title" => title}, socket),
    do: reply(socket, Fude.Issho.change(socket, :chart, &Fude.title(&1, title)))

  def handle_event("note", %{"text" => text}, socket),
    do:
      reply(
        socket,
        Fude.Issho.change(socket, :chart, &Fude.annotate(&1, :line, y: 100, text: text))
      )

  def handle_event("line", _params, socket) do
    reply(
      socket,
      Fude.Issho.change(socket, :chart, fn chart ->
        %{chart | layers: chart.layers ++ Fude.rule(y: 100).layers}
      end)
    )
  end

  def handle_event("break", _params, socket) do
    reply(socket, Fude.Issho.change(socket, :chart, fn chart -> %{chart | height: -1} end))
  end

  defp reply(socket, result), do: {:reply, %{"result" => inspect(result)}, socket}
end
