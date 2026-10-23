# The Fude development server: `mix dev`, then http://localhost:4099.
#
# One Phoenix endpoint with a gallery of charts on made-up data, the
# built bundle from priv/static, and a live page whose data changes every
# second. The browser tests in e2e/ run against it.
#
# The bundle rebuilds and the page reloads on a change.
#
# Query params of every page: `locale` (a BCP 47 locale), `theme=sumi`,
# `dark=1`.
#
# Environment:
#
#   * PORT - the HTTP port (4099).
#   * FUDE_DEV_WATCH - "false" starts no esbuild watcher and no live
#     reload, for the browser tests; the bundle must be built first.

port = "PORT" |> System.get_env("4099") |> String.to_integer()
watch? = System.get_env("FUDE_DEV_WATCH") != "false"

Application.put_env(:phoenix, :json_library, JSON)
Logger.configure(level: :info)

Application.put_env(:fude, FudeDev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  code_reloader: watch?,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: port],
  live_view: [signing_salt: "fude-dev-live-view-salt"],
  pubsub_server: FudeDev.PubSub,
  render_errors: [formats: [html: FudeDev.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("fude-development-secret-", 3),
  server: true,
  url: [host: "localhost"],
  watchers:
    if(watch?, do: [fude_esm: {Esbuild, :install_and_run, [:fude_esm, ~w(--watch)]}], else: []),
  live_reload: [patterns: [~r"priv/static/.*\.(js|css)$", ~r"lib/fude/.*\.ex$"]]
)

defmodule FudeDev.Data do
  @moduledoc "Made-up data for the gallery: the same on every run."

  @channels ["Online", "Retail", "Partners"]
  @regions ["North", "South", "East", "West", "Central"]

  # A number from a seed: the same on every run.
  defp noise(seed), do: :erlang.phash2(seed, 10_000) / 10_000

  def monthly do
    for month <- 0..23, {channel, i} <- Enum.with_index(@channels) do
      date = Date.add(~D[2025-01-01], 0) |> Date.shift(month: month)
      base = [42_000, 30_000, 12_000] |> Enum.at(i)
      growth = [1.035, 1.004, 1.06] |> Enum.at(i)
      season = 1 + 0.12 * :math.sin((month + 2) / 12 * 2 * :math.pi())

      %{
        month: date,
        channel: channel,
        revenue:
          round(base * :math.pow(growth, month) * season * (0.92 + 0.16 * noise({month, i})))
      }
    end
  end

  def regions do
    for {region, r} <- Enum.with_index(@regions), {channel, c} <- Enum.with_index(@channels) do
      %{
        region: region,
        channel: channel,
        revenue:
          round(20_000 + 60_000 * noise({region, channel}) * (1 - r * 0.12) * (1 - c * 0.2))
      }
    end
  end

  def orders do
    for i <- 1..1200 do
      # A long tail: most orders are small.
      total = 8 + :math.pow(noise({:order, i}), 2.4) * 480 + noise({:o, i}) * 30

      %{
        id: i,
        total: Float.round(total, 2),
        items: 1 + round(noise({:items, i}) * 7),
        channel: Enum.at(@channels, rem(i, 3))
      }
    end
  end

  def activity do
    days = ~w(Mon Tue Wed Thu Fri Sat Sun)

    for {day, d} <- Enum.with_index(days), hour <- 6..22 do
      work =
        if d < 5,
          do: :math.exp(-:math.pow((hour - 14) / 4, 2)),
          else: :math.exp(-:math.pow((hour - 11) / 5, 2)) * 0.6

      %{
        day: day,
        hour: "#{String.pad_leading(to_string(hour), 2, "0")}:00",
        events: round(work * 900 * (0.8 + 0.4 * noise({day, hour})))
      }
    end
  end

  def status do
    [
      %{status: "Delivered", orders: 4120},
      %{status: "Shipped", orders: 1630},
      %{status: "Processing", orders: 870},
      %{status: "Returned", orders: 240}
    ]
  end

  def customers do
    for i <- 1..160 do
      spend = 200 + noise({:spend, i}) * 4800

      %{
        customer: i,
        spend: Float.round(spend, 0),
        orders: round(spend / 180 * (0.6 + 0.8 * noise({:ord, i}))),
        tenure: round(noise({:t, i}) * 48) + 1,
        channel: Enum.at(@channels, rem(i, 3))
      }
    end
  end

  def daily do
    for day <- 0..89 do
      %{
        day: Date.add(~D[2026-07-01], day),
        visits:
          round(
            3200 + 900 * :math.sin(day / 7 * 2 * :math.pi()) + day * 22 + 600 * noise({:v, day})
          )
      }
    end
  end

  def kpis, do: [%{mrr: 184_320.5, last: 171_240.0, done: 68}]
end

defmodule FudeDev.Layouts do
  @moduledoc """
  The root layout: the style sheets, the import map and the LiveSocket.
  `?theme=sumi` also loads fude-sumi.css.
  """
  use Phoenix.Component

  def root(assigns) do
    assigns = assign(assigns, :sumi, assigns.conn.params["theme"] == "sumi")

    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme={@conn.params["dark"] && "dark"} class={@conn.params["dark"] && "dark"}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Fude development</title>
        <link :if={@sumi} rel="preconnect" href="https://fonts.googleapis.com" />
        <link :if={@sumi} rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600&display=swap" />
        <link rel="stylesheet" href="/assets/fude.css" />
        <link :if={@sumi} rel="stylesheet" href="/assets/fude-sumi.css" />
        <style>
          body { font-family: system-ui, sans-serif; margin: 0; background: var(--fude-surface); color: var(--fude-text); }
          main { max-width: 72rem; margin: 0 auto; padding: 2rem 1rem 4rem; }
          nav { display: flex; flex-wrap: wrap; gap: 1rem; margin-bottom: 2rem; font-size: 0.875rem; }
          nav a { color: inherit; }
          .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 30rem), 1fr)); gap: 3rem 3rem; }
          .numbers { display: grid; grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr)); gap: 2rem; margin-bottom: 3rem; }
          button { font: inherit; }
        </style>
        <script type="importmap">
          {
            "imports": {
              "phoenix": "/vendor/phoenix/phoenix.mjs",
              "phoenix_live_view": "/vendor/phoenix_live_view/phoenix_live_view.esm.js",
              "fude": "/assets/fude.esm.js"
            }
          }
        </script>
        <script type="module">
          import { Socket } from "phoenix"
          import { LiveSocket } from "phoenix_live_view"
          import { Fude } from "fude"

          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
          const liveSocket = new LiveSocket("/live", Socket, { hooks: { Fude }, params: { _csrf_token: csrfToken } })
          liveSocket.connect()
          window.liveSocket = liveSocket
        </script>
      </head>
      <body>
        <main>
          <nav>
            <a href="/">Gallery</a><a href="/live">Live</a><a href="?theme=sumi">Sumi</a><a href="?dark=1">Dark</a><a href="?theme=sumi&dark=1">Sumi, dark</a><a href="?locale=de-DE">de-DE</a>
          </nav>
          {@inner_content}
        </main>
      </body>
    </html>
    """
  end
end

defmodule FudeDev.GalleryLive do
  use Phoenix.LiveView

  import Fude.Components

  alias FudeDev.Data

  def mount(params, _session, socket) do
    {:ok, assign(socket, locale: params["locale"] || "en-GB", shuffled: false)}
  end

  def render(assigns) do
    ~H"""
    <div class="numbers">
      <.chart id="mrr" locale={@locale} chart={Fude.number(Data.kpis(), value: [field: :mrr, format: {:currency, "EUR"}], label: "Monthly recurring revenue")} />
      <.chart id="mrr-trend" locale={@locale} chart={Fude.trend(Data.kpis(), value: [field: :mrr, format: :compact], compare: :last, label: "vs last month")} />
      <.chart id="done" locale={@locale} chart={Fude.progress(Data.kpis(), value: :done, goal: 100, label: "Onboarding done, of 100")} />
      <.chart id="visits-spark" locale={@locale} chart={Fude.sparkline(Data.daily(), x: :day, y: :visits, title: "Visits, 90 days")} />
    </div>
    <p><button phx-click="shuffle">Change the data</button></p>
    <div class="grid">
      <.chart
        id="revenue-lines"
        locale={@locale}
        chart={Fude.line(monthly(@shuffled), x: :month, y: [field: :revenue, format: {:currency, "EUR"}, title: "Revenue"], color: :channel,
          title: "Online keeps growing", subtitle: "Monthly revenue by channel, 2025–2026", source: "Made-up data", curve: :monotone)}
      />
      <.chart
        id="revenue-regions"
        locale={@locale}
        chart={Fude.bar(regions(@shuffled), x: [field: :region, sort: :"-y"], y: [field: :revenue, format: {:currency, "EUR"}], color: :channel,
          title: "Revenue by region", subtitle: "Stacked by channel")}
      />
      <.chart
        id="orders-histogram"
        locale={@locale}
        chart={Fude.histogram(Data.orders(), x: [field: :total, title: "Order total"], bins: 30,
          title: "Most orders are small", subtitle: "1,200 orders by their total")}
      />
      <.chart
        id="customers"
        locale={@locale}
        chart={Fude.scatter(Data.customers(), x: [field: :orders, title: "Orders"], y: [field: :spend, format: {:currency, "EUR"}, title: "Spend"], color: :channel,
          title: "Spend grows with orders", subtitle: "160 customers")}
      />
      <.chart
        id="status"
        locale={@locale}
        chart={Fude.donut(Data.status(), value: :orders, color: :status, title: "Orders by status")}
      />
      <.chart
        id="regions-horizontal"
        locale={@locale}
        chart={Fude.bar(regions(@shuffled), x: [field: :region, sort: :"-y"], y: {:sum, :revenue}, horizontal: true, labels: true,
          title: "Total revenue by region", height: 260)}
      />
      <.chart
        id="activity"
        locale={@locale}
        chart={Fude.heatmap(Data.activity(), x: :hour, y: :day, color: :events, title: "When people use the app", subtitle: "Events by hour of the day")}
      />
      <.chart
        id="visits"
        locale={@locale}
        chart={Fude.layers(Data.daily(), [
          Fude.area(x: :day, y: [field: :visits, title: "Visits"]),
          Fude.rule(y: 4000, label: "Goal: 4,000 a day")
        ], title: "Visits reach the goal", subtitle: "Daily visits, July to September")}
      />
      <.chart
        id="revenue-area"
        locale={@locale}
        chart={Fude.area(monthly(@shuffled), x: :month, y: [field: :revenue, format: :compact, title: "Revenue"], color: :channel, title: "Revenue, stacked")}
      />
      <.chart
        id="broken"
        locale={@locale}
        chart={Fude.bar(Data.regions(), x: :regon, y: :revenue, title: "A chart with a typo")}
      />
    </div>
    """
  end

  defp monthly(false), do: Data.monthly()

  defp monthly(true),
    do:
      Enum.map(
        Data.monthly(),
        &%{&1 | revenue: round(&1.revenue * (0.7 + :rand.uniform() * 0.6))}
      )

  defp regions(false), do: Data.regions()

  defp regions(true),
    do:
      Enum.map(
        Data.regions(),
        &%{&1 | revenue: round(&1.revenue * (0.4 + :rand.uniform() * 1.2))}
      )

  def handle_event("shuffle", _params, socket), do: {:noreply, update(socket, :shuffled, &(!&1))}
end

defmodule FudeDev.LiveLive do
  use Phoenix.LiveView

  import Fude.Components

  def mount(params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(1000, :tick)
    now = System.system_time(:second)
    points = for s <- -59..0, do: point(now + s)
    {:ok, assign(socket, locale: params["locale"] || "en-GB", points: points)}
  end

  defp point(second) do
    load = 40 + 25 * :math.sin(second / 9) + 10 * :rand.uniform()

    %{
      at: DateTime.from_unix!(second),
      load: Float.round(load, 1),
      queue: round(load * 3 + :rand.uniform() * 40)
    }
  end

  def handle_info(:tick, socket) do
    now = System.system_time(:second)
    {:noreply, update(socket, :points, &(Enum.drop(&1, 1) ++ [point(now)]))}
  end

  def render(assigns) do
    ~H"""
    <div class="grid">
      <.chart id="load" locale={@locale} chart={Fude.line(@points, x: :at, y: [field: :load, title: "Load, %"], title: "Load", subtitle: "The last minute, every second")} />
      <.chart id="queue" locale={@locale} chart={Fude.bar(Enum.take(@points, -20), x: {:minute, :at}, y: {:sum, :queue}, title: "Queue")} />
      <.chart id="load-now" locale={@locale} chart={Fude.number(Enum.take(@points, -1), value: :load, label: "Load now, %")} />
    </div>
    """
  end
end

defmodule FudeDev.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_root_layout, html: {FudeDev.Layouts, :root})
  end

  scope "/" do
    pipe_through(:browser)

    live("/", FudeDev.GalleryLive)
    live("/live", FudeDev.LiveLive)
  end
end

defmodule FudeDev.ErrorHTML do
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule FudeDev.Endpoint do
  use Phoenix.Endpoint, otp_app: :fude

  @session [store: :cookie, key: "_fude_dev", signing_salt: "fude-dev"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]])

  if System.get_env("FUDE_DEV_WATCH") != "false" do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.Static, at: "/assets", from: Path.expand("priv/static", __DIR__))
  plug(Plug.Static, at: "/vendor/phoenix", from: {:phoenix, "priv/static"})
  plug(Plug.Static, at: "/vendor/phoenix_live_view", from: {:phoenix_live_view, "priv/static"})

  plug(Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: JSON)
  plug(Plug.Session, @session)
  plug(FudeDev.Router)
end

# The script's process ends after this file, so the server runs in a task
# that stays alive; `mix run --no-halt` keeps the VM up.
Task.async(fn ->
  if watch?, do: {:ok, _apps} = Application.ensure_all_started(:esbuild)

  {:ok, _pid} =
    Supervisor.start_link(
      [{Phoenix.PubSub, name: FudeDev.PubSub}, FudeDev.Endpoint],
      strategy: :one_for_one
    )

  IO.puts("Fude development server: http://localhost:#{port}")
  Process.sleep(:infinity)
end)
