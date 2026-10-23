if Code.ensure_loaded?(Issho.Place) do
  defmodule Fude.Issho.Place do
    @moduledoc """
    A place in a chart, in the chart's own terms (its data, never pixels,
    as each person has the chart at their own size): where a person's
    pointer is, where an agent points (Issho's `point` tool). Its format is
    part of Fude's public API, and only grows.

        %{"datum" => %{"x" => "Europe", "color" => "Online"}}  # a bar
        %{"datum" => %{"x" => "2026-03-01"}}                   # a time on a line chart
        %{"datum" => %{"x" => 120, "y" => 4.5}}                # a point of a scatter
        %{"datum" => %{"region" => "BRA"}}                     # a region of a map
        %{"datum" => %{"x" => "Europe"}, "x" => 0.5, "y" => 0.2}

    `"datum"` names a mark by the values of its channels (`x`, `y`,
    `color`, `region`): a category as its name, a time as ISO 8601 text, a
    number as it is, a region by any of its codes or its name. A mark that
    its values do not name all of (a time of a line chart with several
    lines) is the place across the plot at that value. `"x"` and `"y"`
    are where in that place, from 0 to 1, as Issho draws a pointer. In
    the room, it is the `"at"` of a place of the chart's document:
    `%{"doc" => "report:7", "at" => %{"datum" => %{"x" => "Europe"}}}`.
    """
    @behaviour Issho.Place

    @channels ~w(x y color region)

    @impl true
    def validate(nil), do: :ok

    def validate(%{"datum" => %{} = datum} = place) when map_size(datum) > 0 do
      if Enum.all?(datum, &value?/1) and Enum.all?(Map.delete(place, "datum"), &fraction?/1),
        do: :ok,
        else: {:error, :invalid_place}
    end

    def validate(_other), do: {:error, :invalid_place}

    defp value?({channel, value}) when channel in @channels,
      do: (is_binary(value) and byte_size(value) <= 200) or is_number(value)

    defp value?(_other), do: false

    defp fraction?({coordinate, value}) when coordinate in ["x", "y"],
      do: is_number(value) and value >= 0 and value <= 1

    defp fraction?(_other), do: false
  end
end
