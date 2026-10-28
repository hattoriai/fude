defmodule Fude.Annotation do
  @moduledoc """
  A note on a chart, at a place of its data: what a graphics desk writes
  on a chart to tell its story.

      chart
      |> Fude.annotate(:label, x: "North", y: 136_000, text: "Best quarter on record")
      |> Fude.annotate(:band, x: {~D[2026-03-01], ~D[2026-05-01]}, text: "Launch")
      |> Fude.annotate(:line, y: 4000, text: "Goal")

  The places are values of the data, on the chart's own scales: a
  category's name, a date, a number.

    * `:label` - words with a line to a point (`x` and `y`; with `x`
      alone, the top of the chart at that `x`).
    * `:band` - a shaded range of `x` or of `y` (`{from, to}`), with words
      at its top.
    * `:line` - a line across the chart at an `x` or a `y`, with words.
      With both, and one of them a category, the line crosses that
      category's band only: `x: 116, y: "Seats"` marks a majority on the
      bar of seats, not on the bar of votes.
  """

  @type type :: :label | :band | :line
  @type place :: term() | {term(), term()}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          type: type(),
          x: place(),
          y: place(),
          text: String.t() | nil
        }

  defstruct [:id, :type, :x, :y, :text]

  @types [:label, :band, :line]

  @doc "An annotation of a type; raises an `ArgumentError` that says what is wrong."
  @spec new(type(), keyword()) :: t()
  def new(type, opts) when type in @types do
    # Places are kept as a spec has them (a date as its ISO 8601 text), so
    # that a chart and its loaded spec are the same.
    annotation = %__MODULE__{
      type: type,
      x: opts |> Keyword.get(:x) |> plain(),
      y: opts |> Keyword.get(:y) |> plain(),
      text: Keyword.get(opts, :text)
    }

    case Keyword.keys(opts) -- [:x, :y, :text] do
      [] ->
        :ok

      keys ->
        raise ArgumentError, "Fude: an annotation takes :x, :y and :text, got: #{inspect(keys)}"
    end

    case check(annotation) do
      :ok -> annotation
      {:error, message} -> raise ArgumentError, "Fude: " <> message
    end
  end

  def new(type, _opts),
    do:
      raise(
        ArgumentError,
        "Fude: an annotation is a :label, a :band or a :line, got: #{inspect(type)}"
      )

  @doc false
  # Whether an annotation says enough to be drawn.
  @spec check(t()) :: :ok | {:error, String.t()}
  def check(%__MODULE__{type: :label, x: nil, y: nil}), do: {:error, "a label needs an x or a y"}

  def check(%__MODULE__{type: :band, x: x, y: y}) when not is_tuple(x) and not is_tuple(y),
    do: {:error, "a band needs an x or a y of {from, to}"}

  def check(%__MODULE__{type: :line, x: nil, y: nil}), do: {:error, "a line needs an x or a y"}

  def check(%__MODULE__{text: text}) when not is_nil(text) and not is_binary(text),
    do: {:error, "the text of an annotation is a string, got: #{inspect(text)}"}

  def check(%__MODULE__{id: id}) when not is_nil(id) and not is_binary(id),
    do: {:error, "the id of an annotation is a string, got: #{inspect(id)}"}

  def check(%__MODULE__{}), do: :ok

  @doc false
  # The annotation as plain data, for a spec: a date as its ISO 8601 text,
  # a range as `{"from", "to"}`.
  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = annotation) do
    %{"type" => Atom.to_string(annotation.type)}
    |> put("id", annotation.id)
    |> put("x", annotation.x)
    |> put("y", annotation.y)
    |> put("text", annotation.text)
  end

  defp plain({from, to}), do: {value(from), value(to)}
  defp plain(value), do: value(value)

  defp put(map, _key, nil), do: map

  defp put(map, key, {from, to}),
    do: Map.put(map, key, %{"from" => value(from), "to" => value(to)})

  defp put(map, key, value), do: Map.put(map, key, value(value))

  defp value(%Date{} = date), do: Date.to_iso8601(date)
  defp value(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp value(%NaiveDateTime{} = time), do: NaiveDateTime.to_iso8601(time)

  defp value(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp value(value), do: value

  @doc false
  # The annotation of a spec's map, or the error of it.
  @spec load(term()) :: {:ok, t()} | {:error, String.t()}
  def load(%{"type" => type} = map) when type in ~w(label band line) do
    annotation = %__MODULE__{
      id: map["id"],
      type: String.to_existing_atom(type),
      x: place(map["x"]),
      y: place(map["y"]),
      text: map["text"]
    }

    with :ok <- check(annotation), do: {:ok, annotation}
  end

  def load(%{"type" => type}),
    do: {:error, "is a #{inspect(type)}, not a label, a band or a line"}

  def load(other), do: {:error, "must be a map with a \"type\", got: #{inspect(other)}"}

  defp place(%{"from" => from, "to" => to}), do: {from, to}
  defp place(value), do: value
end
