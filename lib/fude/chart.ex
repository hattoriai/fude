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
  def split(opts), do: Keyword.split(opts, [:height, :data | @words])

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

      {key, value}, _chart ->
        raise ArgumentError, "Fude: #{inspect(key)} of a chart is not valid: #{inspect(value)}"
    end)
  end

  @doc "The chart's kind: the kind of its first layer."
  @spec kind(t()) :: Layer.kind() | nil
  def kind(%__MODULE__{layers: [%Layer{kind: kind} | _]}), do: kind
  def kind(%__MODULE__{}), do: nil
end
