defmodule Fude.Names do
  @moduledoc false
  # "Did you mean" for the errors: the closest of the names, when it is
  # close enough to be a typo.

  @spec suggest(atom() | String.t(), [atom() | String.t()]) :: String.t()
  def suggest(name, names) do
    case closest(name, names) do
      nil -> ""
      found -> "; did you mean #{inspect(found)}?"
    end
  end

  @spec closest(atom() | String.t(), [atom() | String.t()]) :: atom() | String.t() | nil
  def closest(name, names) do
    name = to_string(name)

    names
    |> Enum.map(&{&1, String.jaro_distance(name, to_string(&1))})
    |> Enum.filter(fn {_name, distance} -> distance >= 0.8 end)
    |> Enum.max_by(fn {_name, distance} -> distance end, fn -> {nil, 0} end)
    |> elem(0)
  end
end
