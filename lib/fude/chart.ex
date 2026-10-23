defmodule Fude.Chart do
  @moduledoc """
  A chart: its layers, its words (title, subtitle, caption, source), and
  the data it draws.

  The functions of `Fude` make charts; `Fude.Spec` dumps one to plain data
  to save and loads it back. A chart's data is not part of its spec: a
  saved chart names its data (`data`, `"data"` by default), and gets it
  again when it draws (`<.chart spec={...} data={...}>`).
  """

  alias Fude.Layer

  @type t :: %__MODULE__{
          layers: [Layer.t()],
          title: String.t() | nil,
          subtitle: String.t() | nil,
          caption: String.t() | nil,
          source: String.t() | nil,
          description: String.t() | nil,
          data: String.t(),
          height: pos_integer() | nil,
          animate: boolean() | %{duration: non_neg_integer()},
          frame: String.t() | nil,
          annotations: [Fude.Annotation.t()],
          facet: %{field: String.t(), columns: pos_integer() | nil} | nil,
          datasets: %{String.t() => term()}
        }

  defstruct layers: [],
            title: nil,
            subtitle: nil,
            caption: nil,
            source: nil,
            description: nil,
            data: "data",
            height: nil,
            animate: true,
            frame: nil,
            annotations: [],
            facet: nil,
            datasets: %{}

  @words [:title, :subtitle, :caption, :source, :description]

  @doc false
  def words, do: @words

  @doc false
  # Puts the keys of a chart (not of a layer) from the keyword list that
  # the functions of Fude take; the rest are the layer's.
  @spec split(keyword()) :: {keyword(), keyword()}
  def split(opts), do: Keyword.split(opts, [:height, :data, :animate, :frame | @words])

  @doc false
  @spec put(t(), keyword()) :: t()
  def put(chart, opts) do
    Enum.reduce(opts, chart, fn
      {key, value}, chart when key in @words and (is_binary(value) or is_nil(value)) ->
        Map.put(chart, key, value)

      {:height, height}, chart when is_integer(height) and height > 0 ->
        %{chart | height: height}

      {:data, name}, chart when is_binary(name) or is_atom(name) ->
        %{chart | data: to_string(name)}

      {:animate, animate}, chart ->
        %{chart | animate: animate!(animate)}

      {:frame, frame}, chart when is_binary(frame) or is_nil(frame) ->
        %{chart | frame: frame}

      {key, value}, _chart ->
        raise ArgumentError, "Fude: #{inspect(key)} of a chart is not valid: #{inspect(value)}"
    end)
  end

  @doc false
  # Whether a chart's marks move, and for how long: `true` (the theme's
  # duration), `false` (never), or `[duration: ms]`.
  def animate!(animate) when is_boolean(animate), do: animate

  def animate!(duration: ms) when is_integer(ms) and ms >= 0 and ms <= 10_000,
    do: %{duration: ms}

  def animate!(%{duration: ms}) when is_integer(ms) and ms >= 0 and ms <= 10_000,
    do: %{duration: ms}

  def animate!(other),
    do:
      raise(
        ArgumentError,
        "Fude: :animate of a chart must be true, false or [duration: ms] (0 to 10000), got: #{inspect(other)}"
      )

  @doc "The chart's kind: the kind of its first layer."
  @spec kind(t()) :: Layer.kind() | nil
  def kind(%__MODULE__{layers: [%Layer{kind: kind} | _]}), do: kind
  def kind(%__MODULE__{}), do: nil
end
