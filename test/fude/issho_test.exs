defmodule Fude.IsshoTest do
  # Shared charts: a chart's spec as a shared state of an Issho room,
  # changed by people (in LiveViews) and agents (with tools) alike.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Fude.Issho.Place
  alias Issho.Tool.Context

  doctest Fude.Issho

  @endpoint FudeTest.Endpoint
  @instance FudeTest.Issho

  setup do
    id = Integer.to_string(System.unique_integer([:positive]))
    room = "report:" <> id
    Process.register(self(), FudeTest.Reports.owner(room))
    %{room: room, conn: build_conn()}
  end

  defp open(conn, room, user),
    do: live_isolated(conn, FudeTest.SharedLive, session: %{"room" => room, "user" => user})

  # Waits until a LiveView has handled what is in its mailbox.
  defp settle(view) do
    :sys.get_state(view.pid)
    :sys.get_state(view.pid)
  end

  defp click(view, event, params \\ %{}) do
    view |> element("#revenue") |> render_hook(event, params)
    settle(view)
  end

  defp agent, do: Context.new(@instance, %{id: "agent:claude", name: "Claude", kind: :agent})

  defp call(tool, args),
    do: Issho.Tools.call(Fude.Issho.tools() ++ Issho.Tools.room(), tool, args, agent())

  describe "state/1 and ops/2" do
    test "a shared chart has its layers in a list, each with an id" do
      state = Fude.Issho.state(FudeTest.Reports.chart())

      assert %{"layers" => [%{"id" => "l" <> _, "kind" => "bar"}], "title" => "Revenue"} = state
      assert {:ok, chart} = Fude.Spec.load(state)
      assert Fude.Spec.dump(chart, layers: true) == state
    end

    test "changes of keys are sets and deletes; a layer is changed by its id" do
      before = %{
        "fude" => 1,
        "title" => "Revenue",
        "layers" => [
          %{"id" => "a", "kind" => "bar", "x" => "region"},
          %{"id" => "b", "kind" => "rule"}
        ]
      }

      after_ = %{
        "fude" => 1,
        "subtitle" => "By region",
        "layers" => [
          %{"id" => "a", "kind" => "bar", "x" => "channel"},
          %{"id" => "b", "kind" => "rule"}
        ]
      }

      assert Fude.Issho.ops(before, after_) == [
               %{"op" => "set", "path" => ["layers", "a", "x"], "value" => "channel"},
               %{"op" => "set", "path" => ["subtitle"], "value" => "By region"},
               %{"op" => "delete", "path" => ["title"]}
             ]
    end

    test "layers are inserted, moved and removed by their ids" do
      a = %{"id" => "a", "kind" => "bar"}
      b = %{"id" => "b", "kind" => "line"}
      c = %{"id" => "c", "kind" => "rule"}
      d = %{"id" => "d", "kind" => "text"}

      assert Fude.Issho.ops(%{"layers" => [a, b, c]}, %{"layers" => [c, a, d]}) == [
               %{"op" => "delete", "path" => ["layers", "b"]},
               %{"op" => "move", "path" => ["layers"], "id" => "c", "at" => "start"},
               %{"op" => "insert", "path" => ["layers"], "value" => d, "after" => "a"}
             ]
    end

    test "the operations make the one state into the other in Issho's map engine" do
      check = fn before, after_ ->
        {:ok, state} = Issho.Engine.Map.apply(before, Fude.Issho.ops(before, after_), [])
        assert state == after_
      end

      items = for id <- ~w(a b c d e), do: %{"id" => id, "kind" => "bar", "n" => id}

      for _ <- 1..50 do
        before = Enum.take_random(items, Enum.random(1..5))

        after_ =
          items
          |> Enum.take_random(Enum.random(1..5))
          |> Enum.map(fn item ->
            if :rand.uniform(2) == 1, do: %{item | "n" => "changed"}, else: item
          end)

        check.(%{"layers" => before, "title" => "A"}, %{"layers" => after_, "caption" => "B"})
      end
    end
  end

  describe "the place of a chart" do
    test "a datum by its channels' values, with fractions within it" do
      assert Place.validate(%{"datum" => %{"x" => "Europe", "color" => "Online"}}) == :ok
      assert Place.validate(%{"datum" => %{"x" => 120, "y" => 4.5}, "x" => 0.5, "y" => 1}) == :ok
      assert Place.validate(%{"datum" => %{"region" => "BRA"}}) == :ok
      assert Place.validate(nil) == :ok

      assert Place.validate(%{"datum" => %{}}) == {:error, :invalid_place}
      assert Place.validate(%{"datum" => %{"size" => 3}}) == {:error, :invalid_place}
      assert Place.validate(%{"datum" => %{"x" => %{}}}) == {:error, :invalid_place}
      assert Place.validate(%{"datum" => %{"x" => "a"}, "x" => 2}) == {:error, :invalid_place}
      assert Place.validate(%{"cell" => [1, "a"]}) == {:error, :invalid_place}
    end
  end

  describe "people" do
    test "a change in one LiveView is the chart of every LiveView of the room", %{
      conn: conn,
      room: room
    } do
      {:ok, ada, _} = open(conn, room, "user:ada")
      {:ok, ken, _} = open(conn, room, "user:ken")

      click(ada, "title", %{"title" => "Online leads"})
      settle(ken)

      assert ken |> element("#revenue .fude-title") |> render() =~ "Online leads"
      assert_receive {:saved, %Fude.Chart{title: "Online leads"}, _by}

      assert ken |> element("#revenue") |> render() =~ ~s(data-issho-doc="#{room}")
    end

    test "two changes at once both stay", %{conn: conn, room: room} do
      {:ok, ada, _} = open(conn, room, "user:ada")
      {:ok, ken, _} = open(conn, room, "user:ken")

      click(ada, "note", %{"text" => "Goal"})
      click(ken, "line")
      click(ken, "title", %{"title" => "With a goal"})
      settle(ada)

      for view <- [ada, ken] do
        chart = Fude.Test.chart(view, "revenue")
        assert chart["title"] == "With a goal"
        assert length(chart["layers"]) == 2
        assert [%{"text" => "Goal"}] = chart["annotations"]
      end
    end

    test "a change that makes the chart invalid is refused, with why", %{conn: conn, room: room} do
      {:ok, ada, _} = open(conn, room, "user:ada")

      ada |> element("#revenue") |> render_hook("break")
      assert_reply(ada, %{"result" => result})
      assert {:error, message} = result |> Code.eval_string() |> elem(0)
      assert message =~ "height: must be a whole number of pixels"
      assert Fude.Test.chart(ada, "revenue")["title"] == "Revenue"
    end
  end

  describe "agents" do
    test "read_chart gives the spec and what the chart shows", %{conn: conn, room: room} do
      {:ok, _ada, _} = open(conn, room, "user:ada")

      assert {:ok, %{"spec" => spec, "shows" => shows}} = call("read_chart", %{"room" => room})
      assert %{"layers" => [%{"id" => _, "kind" => "bar"}]} = spec
      assert shows["title"] == "Revenue"
      assert shows["columns"] == ["Region", "Revenue", "Channel"]
      assert ["North", 120, "Online"] in shows["rows"]
      assert shows["row_count"] == 4
    end

    test "change_chart sends what changed, as a person's change", %{conn: conn, room: room} do
      {:ok, ada, _} = open(conn, room, "user:ada")
      {:ok, %{"spec" => spec}} = call("read_chart", %{"room" => room})

      # An agent that drops the ids changes the layer it had.
      [layer] = spec["layers"]

      new =
        spec
        |> Map.put("title", "Online leads")
        |> Map.put("layers", [
          layer
          |> Map.delete("id")
          |> Map.put("y", %{"field" => "revenue", "aggregate" => "mean"})
        ])

      assert {:ok, %{"changes" => 2}} = call("change_chart", %{"room" => room, "spec" => new})
      settle(ada)

      chart = Fude.Test.chart(ada, "revenue")
      assert chart["title"] == "Online leads"
      assert_receive {:saved, %Fude.Chart{layers: [%{id: id}]}, _by}
      assert id == layer["id"]

      assert {:ok, "Nothing changed."} = call("change_chart", %{"room" => room, "spec" => new})
    end

    test "an invalid spec changes nothing, and says every error", %{conn: conn, room: room} do
      {:ok, ada, _} = open(conn, room, "user:ada")
      {:ok, %{"spec" => spec}} = call("read_chart", %{"room" => room})
      [layer] = spec["layers"]

      bad =
        Map.put(spec, "layers", [
          Map.put(layer, "y", %{"field" => "revenue", "aggregate" => "summ"})
        ])

      assert {:error, message} = call("change_chart", %{"room" => room, "spec" => bad})
      assert message =~ ~s(layers.#{layer["id"]}.y.aggregate: must be one of)
      refute message =~ "is missing"
      assert message =~ ~s(did you mean "sum"?)

      # Issho's own update_state passes the same check.
      ops = [%{"op" => "set", "path" => ["layers", layer["id"], "kind"], "value" => "barr"}]
      assert {:error, refused} = call("update_state", %{"room" => room, "ops" => ops})
      assert refused =~ "layers.#{layer["id"]}.kind: must be a kind of chart"

      settle(ada)
      assert Fude.Test.chart(ada, "revenue")["title"] == "Revenue"
    end

    test "an agent points at a mark with Issho's point tool", %{conn: conn, room: room} do
      {:ok, _ada, _} = open(conn, room, "user:ada")
      at = %{"datum" => %{"x" => "North", "color" => "Online"}}

      assert {:ok, "Pointing at it."} = call("point", %{"room" => room, "at" => at})
      assert {:error, _reason} = call("point", %{"room" => room, "at" => %{"cell" => [1, "a"]}})
    end
  end
end
