defmodule Fude.TestTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Fude.Test

  @endpoint FudeTest.Endpoint

  setup do
    {:ok, view, _html} = live(build_conn(), "/sales")
    %{view: view}
  end

  test "reads the chart's kind, title and series", %{view: view} do
    assert kind(view, "revenue") == "bar"
    assert title(view, "revenue") == "Revenue"
    assert series(view, "revenue") == ["Online", "Retail"]
  end

  test "reads the data by the titles of the columns", %{view: view} do
    assert data(view, "revenue") == [
             %{"Region" => "North", "Revenue" => 120, "Channel" => "Online"},
             %{"Region" => "North", "Revenue" => 80, "Channel" => "Retail"},
             %{"Region" => "South", "Revenue" => 60, "Channel" => "Online"},
             %{"Region" => "South", "Revenue" => 90, "Channel" => "Retail"}
           ]
  end

  test "sees the data change", %{view: view} do
    view |> element("button", "More") |> render_click()
    assert %{"Region" => "East", "Revenue" => 40} = hd(data(view, "revenue"))
  end

  test "reads the description", %{view: view} do
    assert description(view, "revenue") =~ "A bar chart"
    assert error(view, "revenue") == nil
  end

  test "fails on a chart that is not there", %{view: view} do
    assert_raise ExUnit.AssertionError, ~r/no chart/, fn -> chart(view, "nope") end
  end

  test "Fude.Live.append sends only the new rows, compiled", %{view: view} do
    render_hook(view, "stream", %{})

    assert_push_event(view, "fude:append", %{
      id: "revenue",
      max: 50,
      wire: %{"layers" => [%{"n" => 1}], "scales" => %{"x" => %{"domain" => ["West"]}}}
    })
  end
end
