defmodule Fude.Rules do
  @moduledoc """
  The rules of a chart's scales that the server and the browser both
  apply: nice domains, the ticks of a number axis and of a time axis, the
  bins of a histogram and the units of a time.

  They are written twice, here and in `assets/src/rules.ts`, word for
  word: a change here is a change there. One fixture,
  `test/fixtures/rules.json`, holds the cases that both test suites run.

  Times are milliseconds since 1970 in UTC.
  """

  # The thresholds of the steps of ticks: 1, 2, 5 and 10 times a power of
  # ten, chosen by the step's distance from each.
  @e10 :math.sqrt(50)
  @e5 :math.sqrt(10)
  @e2 :math.sqrt(2)

  @second 1000
  @minute 60 * @second
  @hour 60 * @minute
  @day 24 * @hour
  @week 7 * @day
  @month 30 * @day
  @year 365 * @day

  @doc """
  The step between ticks of about `count` ticks from `start` to `stop`: a
  positive number, or, for a step under 1, minus its inverse (`-10` is a
  step of 0.1), which keeps it exact.
  """
  @spec increment(number(), number(), number()) :: number()
  def increment(start, stop, count) do
    step = (stop - start) / max(0, count)
    power = Float.floor(:math.log10(step))
    error = step / :math.pow(10, power)
    factor = factor(error)

    if power >= 0,
      do: factor * :math.pow(10, power),
      else: -:math.pow(10, -power) / factor
  end

  defp factor(error) when error >= @e10, do: 10
  defp factor(error) when error >= @e5, do: 5
  defp factor(error) when error >= @e2, do: 2
  defp factor(_error), do: 1

  @doc "About `count` ticks between `start` and `stop`, at round numbers, in order."
  @spec ticks(number(), number(), number()) :: [float()]
  def ticks(start, stop, count) do
    cond do
      count <= 0 -> []
      start == stop -> [start / 1]
      stop < start -> start |> ticks_up(stop, count) |> Enum.reverse()
      true -> ticks_up(stop, start, count)
    end
  end

  defp ticks_up(stop, start, count) do
    case spec(start, stop, count) do
      {i1, i2, _inc} when i2 < i1 -> []
      {i1, i2, inc} when inc < 0 -> for i <- i1..i2//1, do: i / -inc
      {i1, i2, inc} -> for i <- i1..i2//1, do: i * inc
    end
  end

  defp spec(start, stop, count) do
    step = (stop - start) / max(0, count)
    power = Float.floor(:math.log10(step))
    error = step / :math.pow(10, power)
    factor = factor(error)

    {i1, i2, inc} =
      if power < 0 do
        inc = :math.pow(10, -power) / factor
        i1 = round_half_up(start * inc)
        i2 = round_half_up(stop * inc)
        i1 = if i1 / inc < start, do: i1 + 1, else: i1
        i2 = if i2 / inc > stop, do: i2 - 1, else: i2
        {i1, i2, -inc}
      else
        inc = :math.pow(10, power) * factor
        i1 = round_half_up(start / inc)
        i2 = round_half_up(stop / inc)
        i1 = if i1 * inc < start, do: i1 + 1, else: i1
        i2 = if i2 * inc > stop, do: i2 - 1, else: i2
        {i1, i2, inc}
      end

    if i2 < i1 and 0.5 <= count and count < 2,
      do: spec(start, stop, count * 2),
      else: {i1, i2, inc}
  end

  # As JavaScript's Math.round: halves go up.
  defp round_half_up(x) do
    floor = Float.floor(x)
    if x - floor >= 0.5, do: trunc(floor) + 1, else: trunc(floor)
  end

  @doc """
  The domain from `start` to `stop` widened to round numbers, so that its
  ends are ticks of about `count` ticks. A domain of one value widens
  around it.
  """
  @spec nice(number(), number(), number()) :: {number(), number()}
  def nice(start, stop, count \\ 10)

  def nice(value, value, _count) when value == 0, do: {0, 1}

  def nice(value, value, count) do
    pad = abs(value) / 10
    nice(value - pad, value + pad, count)
  end

  def nice(start, stop, count) when start > stop do
    {stop, start} = nice(stop, start, count)
    {start, stop}
  end

  def nice(start, stop, count), do: nice(start, stop, count, nil, 10)

  defp nice(start, stop, _count, _prestep, 0), do: {start, stop}

  defp nice(start, stop, count, prestep, left) do
    step = increment(start, stop, count)

    cond do
      step == prestep ->
        {start, stop}

      step > 0 ->
        nice(
          Float.floor(start / step) * step,
          Float.ceil(stop / step) * step,
          count,
          step,
          left - 1
        )

      step < 0 ->
        nice(
          Float.ceil(start * step) / step,
          Float.floor(stop * step) / step,
          count,
          step,
          left - 1
        )

      true ->
        {start, stop}
    end
  end

  @doc """
  The bins of the numbers from `min` to `max`, about `count` of them, at
  round numbers: `{start, step, n}`, the first bin `[start, start + step)`
  and the last one closed, so that `max` is in it.
  """
  @spec bins(number(), number(), pos_integer()) :: {number(), number(), pos_integer()}
  def bins(min, max, _count) when min == max, do: {min / 1, 1.0, 1}

  def bins(min, max, count) do
    inc = increment(min, max, count)
    step = if inc < 0, do: 1 / -inc, else: inc / 1
    start = Float.floor(min / step) * step
    n = max(1, ceil((max - start) / step))
    # A max at a bin's start goes in the bin before, which is closed.
    n = if start + n * step < max, do: n + 1, else: n
    {start, step, n}
  end

  @doc "The bin of a value among the bins `{start, step, n}`: from 0 to `n - 1`."
  @spec bin({number(), number(), pos_integer()}, number()) :: non_neg_integer()
  def bin({start, step, n}, value),
    do: value |> Kernel.-(start) |> Kernel./(step) |> floor() |> max(0) |> min(n - 1)

  @doc """
  The start of a time's unit: `:minute`, `:hour`, `:day`, `:week` (from
  Monday), `:month`, `:quarter` or `:year`.
  """
  @spec floor(integer(), atom()) :: integer()
  def floor(time, :second), do: Integer.floor_div(time, @second) * @second
  def floor(time, :minute), do: Integer.floor_div(time, @minute) * @minute
  def floor(time, :hour), do: Integer.floor_div(time, @hour) * @hour
  def floor(time, :day), do: Integer.floor_div(time, @day) * @day

  def floor(time, :week) do
    days = Integer.floor_div(time, @day)
    # 1970-01-01 was a Thursday, the fourth day from Monday.
    (days - Integer.mod(days + 3, 7)) * @day
  end

  def floor(time, :month) do
    {year, month, _day} = civil(time)
    days(year, month, 1) * @day
  end

  def floor(time, :quarter) do
    {year, month, _day} = civil(time)
    days(year, month - rem(month - 1, 3), 1) * @day
  end

  def floor(time, :year) do
    {year, _month, _day} = civil(time)
    days(year, 1, 1) * @day
  end

  @doc "The time `step` units after a time at the start of its unit."
  @spec offset(integer(), atom(), integer()) :: integer()
  def offset(time, :second, step), do: time + step * @second
  def offset(time, :minute, step), do: time + step * @minute
  def offset(time, :hour, step), do: time + step * @hour
  def offset(time, :day, step), do: time + step * @day
  def offset(time, :week, step), do: time + step * @week

  def offset(time, :month, step) do
    {year, month, _day} = civil(time)
    months = year * 12 + (month - 1) + step
    days(Integer.floor_div(months, 12), Integer.mod(months, 12) + 1, 1) * @day
  end

  def offset(time, :quarter, step), do: offset(time, :month, step * 3)
  def offset(time, :year, step), do: offset(time, :month, step * 12)

  # The intervals of time ticks, by their length: a unit and a step.
  @intervals [
    {:second, 1, @second},
    {:second, 5, 5 * @second},
    {:second, 15, 15 * @second},
    {:second, 30, 30 * @second},
    {:minute, 1, @minute},
    {:minute, 5, 5 * @minute},
    {:minute, 15, 15 * @minute},
    {:minute, 30, 30 * @minute},
    {:hour, 1, @hour},
    {:hour, 3, 3 * @hour},
    {:hour, 6, 6 * @hour},
    {:hour, 12, 12 * @hour},
    {:day, 1, @day},
    {:day, 2, 2 * @day},
    {:week, 1, @week},
    {:month, 1, @month},
    {:month, 3, 3 * @month},
    {:year, 1, @year}
  ]

  @doc """
  About `count` ticks of a time axis from `start` to `stop`, at the starts
  of round units: `{unit, step, ticks}`, where the unit says how to write
  them (`:month`: "Mar").
  """
  @spec time_ticks(integer(), integer(), number()) :: {atom(), pos_integer(), [integer()]}
  def time_ticks(start, stop, count) when stop < start do
    {unit, step, ticks} = time_ticks(stop, start, count)
    {unit, step, Enum.reverse(ticks)}
  end

  def time_ticks(start, stop, count) do
    {unit, step} = time_interval(start, stop, count)
    {unit, step, time_range(start, stop, unit, step)}
  end

  @doc false
  def time_interval(start, stop, count) do
    target = abs(stop - start) / count
    i = Enum.find_index(@intervals, fn {_unit, _step, length} -> length > target end)

    cond do
      i == nil ->
        step = increment(start / @year, stop / @year, count)
        {:year, max(1, trunc(if step < 0, do: 1, else: step))}

      i == 0 ->
        {:millisecond, max(1, trunc(max(increment(start, stop, count), 1)))}

      true ->
        {unit_a, step_a, length_a} = Enum.at(@intervals, i - 1)
        {unit_b, step_b, length_b} = Enum.at(@intervals, i)
        if target / length_a < length_b / target, do: {unit_a, step_a}, else: {unit_b, step_b}
    end
  end

  defp time_range(start, stop, :millisecond, step) do
    first = ceil(start / step) * step
    Enum.to_list(first..stop//step)
  end

  defp time_range(start, stop, unit, step) do
    first = floor(start, unit)
    first = if first < start, do: offset(first, unit, 1), else: first

    first
    |> Stream.iterate(&offset(&1, unit, 1))
    |> Stream.take_while(&(&1 <= stop))
    |> Enum.filter(&(rem(field(&1, unit), step) == 0))
  end

  # The field that a step counts: the seconds of the minute, the day of the
  # month from 0, the month from 0, the year.
  defp field(time, :second), do: time |> Integer.floor_div(@second) |> Integer.mod(60)
  defp field(time, :minute), do: time |> Integer.floor_div(@minute) |> Integer.mod(60)
  defp field(time, :hour), do: time |> Integer.floor_div(@hour) |> Integer.mod(24)
  defp field(time, :day), do: time |> civil() |> elem(2) |> Kernel.-(1)
  defp field(_time, :week), do: 0
  defp field(time, :month), do: time |> civil() |> elem(1) |> Kernel.-(1)
  defp field(time, :quarter), do: time |> civil() |> elem(1) |> Kernel.-(1) |> div(3)
  defp field(time, :year), do: time |> civil() |> elem(0)

  # The day of a time in the proleptic Gregorian calendar, and back
  # (Howard Hinnant's algorithms, as Koyomi's iso.ts).
  @doc false
  def civil(time) do
    z = Integer.floor_div(time, @day) + 719_468
    era = Integer.floor_div(z, 146_097)
    doe = z - era * 146_097
    yoe = div(doe - div(doe, 1460) + div(doe, 36_524) - div(doe, 146_096), 365)
    y = yoe + era * 400
    doy = doe - (365 * yoe + div(yoe, 4) - div(yoe, 100))
    mp = div(5 * doy + 2, 153)
    d = doy - div(153 * mp + 2, 5) + 1
    m = if mp < 10, do: mp + 3, else: mp - 9
    {if(m <= 2, do: y + 1, else: y), m, d}
  end

  @doc false
  def days(year, month, day) do
    y = if month <= 2, do: year - 1, else: year
    era = Integer.floor_div(y, 400)
    yoe = y - era * 400
    mp = if month > 2, do: month - 3, else: month + 9
    doy = div(153 * mp + 2, 5) + day - 1
    doe = yoe * 365 + div(yoe, 4) - div(yoe, 100) + doy
    era * 146_097 + doe - 719_468
  end
end
