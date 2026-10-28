defmodule Fude.Test do
  @moduledoc """
  Helpers for testing charts with `Phoenix.LiveViewTest`: they read what a
  chart shows, as the server made it for the browser.

      import Fude.Test

      test "shows the revenue of each region", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/sales")

        assert kind(view, "revenue") == "bar"
        assert series(view, "revenue") == ["Online", "Retail"]
        assert [%{"Region" => "North", "Revenue" => 120, "Channel" => "Online"} | _] = data(view, "revenue")
      end

  Each helper takes the view (or a render of it, a string) and the id of
  the chart. They need `lazy_html`, which the tests of LiveView 1.1 use.
  """

  @compile {:no_warn_undefined, [LazyHTML]}

  import ExUnit.Assertions

  @typedoc "A LiveView under test (a `Phoenix.LiveViewTest.View`), or a render of one."
  @type view :: struct() | String.t()

  @doc "What the server sent the browser for the chart: its kind, scales and layers."
  @spec chart(view(), String.t()) :: map()
  def chart(view, id) do
    case attribute(view, id, "data-fude") do
      nil -> flunk("no chart with the id #{inspect(id)}")
      json -> json |> JSON.decode!() |> Fude.Wire.unpack()
    end
  end

  @doc ~s|The chart's kind: `"bar"`, `"line"`...|
  @spec kind(view(), String.t()) :: String.t()
  def kind(view, id), do: chart(view, id)["kind"]

  @doc "The chart's title, or `nil`."
  @spec title(view(), String.t()) :: String.t() | nil
  def title(view, id), do: chart(view, id)["title"]

  @doc "The names of the chart's series (its colors), in order: `[]` for a chart of one."
  @spec series(view(), String.t()) :: [String.t()]
  def series(view, id) do
    case chart(view, id) do
      %{"scales" => %{"color" => %{"type" => "ordinal", "domain" => domain}}} -> domain
      _ -> []
    end
  end

  @doc """
  The data that the chart draws, as its table has it: a map for each mark,
  by the titles of the columns (`"Region"`, `"Revenue"`), with a category
  by its name and a time as a `Date` or a `DateTime`.
  """
  @spec data(view(), String.t()) :: [map()]
  def data(view, id) do
    {heads, rows} = view |> chart(id) |> Fude.Compile.table()
    Enum.map(rows, &(heads |> Enum.zip(&1) |> Map.new()))
  end

  @doc "What a screen reader says of the chart."
  @spec description(view(), String.t()) :: String.t() | nil
  def description(view, id), do: chart(view, id)["description"]

  @doc "Why the chart does not draw (a field that is not in the data...), or `nil` when it draws."
  @spec error(view(), String.t()) :: String.t() | nil
  def error(view, id) do
    view
    |> document()
    |> LazyHTML.query("##{id} .fude-error")
    |> LazyHTML.text()
    |> String.trim()
    |> blank()
  end

  @doc "The single number of a `Fude.number/2`, `Fude.trend/2` or `Fude.progress/2`."
  @spec value(view(), String.t()) :: number() | String.t() | nil
  def value(view, id), do: get_in(chart(view, id), ["single", "value"])

  defp blank(""), do: nil
  defp blank(text), do: text

  defp attribute(view, id, name) do
    case view |> document() |> LazyHTML.query("##{id}") |> LazyHTML.attribute(name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp document(html) when is_binary(html), do: LazyHTML.from_document(html)
  defp document(view), do: view |> Phoenix.LiveViewTest.render() |> LazyHTML.from_fragment()
end
