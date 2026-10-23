# How long the server takes to make a chart of many rows: `mix run bench/compile.exs`.
# The data is made up, as in dev.exs; the times are the best of five runs.

defmodule FudeBench.Compile do
  @moduledoc false

  def run do
    for n <- [10_000, 100_000, 200_000] do
      data = for i <- 1..n, do: %{x: rem(i, 50), y: i * 1.0, c: "s#{rem(i, 4)}", d: Date.add(~D[2026-01-01], rem(i, 365))}

      report(n, "Data.new", fn -> Fude.Data.new(data) end)
      report(n, "bar, summed by x and color", fn -> {:ok, _} = Fude.Compile.compile(Fude.bar(data, x: :x, y: :y, color: :c)) end)
      report(n, "line by month", fn -> {:ok, _} = Fude.Compile.compile(Fude.line(data, x: {:month, :d}, y: {:sum, :y})) end)
      report(n, "histogram", fn -> {:ok, _} = Fude.Compile.compile(Fude.histogram(data, x: :y, bins: 40)) end)
      report(n, "scatter", fn -> {:ok, _} = Fude.Compile.compile(Fude.scatter(data, x: :x, y: :y, color: :c)) end)
    end
  end

  defp report(n, name, fun) do
    best = Enum.min(for _ <- 1..5, do: elem(:timer.tc(fun), 0))
    IO.puts(String.pad_trailing("#{n} rows, #{name}", 44) <> "#{Float.round(best / 1000, 1)} ms")
  end
end

FudeBench.Compile.run()
