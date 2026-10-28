defmodule Fude.LiveTest do
  use ExUnit.Case, async: true

  describe "brush_range/1" do
    test "gives the dates of a time with a unit of a day or more" do
      assert Fude.Live.brush_range(%{
               "id" => "orders",
               "from" => "2026-03-01",
               "to" => "2026-05-01"
             }) ==
               {~D[2026-03-01], ~D[2026-05-01]}
    end

    test "gives the times of a time of a day" do
      assert Fude.Live.brush_range(%{
               "from" => "2026-03-01T10:30:00Z",
               "to" => "2026-03-01T12:00:00Z"
             }) ==
               {~U[2026-03-01 10:30:00Z], ~U[2026-03-01 12:00:00Z]}
    end

    test "gives numbers as they are" do
      assert Fude.Live.brush_range(%{"from" => 12.5, "to" => 40}) == {12.5, 40}
    end

    test "raises for what is not a brush's" do
      assert_raise ArgumentError, ~r/not a brush's params/, fn ->
        Fude.Live.brush_range(%{"x" => "North"})
      end

      assert_raise ArgumentError, ~r/not a date, a time or a number: "March"/, fn ->
        Fude.Live.brush_range(%{"from" => "March", "to" => "May"})
      end
    end
  end
end
