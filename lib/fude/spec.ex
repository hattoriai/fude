defmodule Fude.Spec do
  @moduledoc """
  A chart as plain data, to save and load back.

      spec = Fude.Spec.dump(chart)
      #=> %{"fude" => 1, "kind" => "bar", "x" => "region", "y" => %{"field" => "revenue", "aggregate" => "sum"}}

      {:ok, chart} = Fude.Spec.load(spec)

  A spec is a map with string keys and JSON values, so it goes into a
  `:map` column, a JSON file or a message as it is, and
  `load(dump(chart))` is the chart again. It carries its version
  (`"fude" => 1`): `load/1` takes the specs of every earlier version and
  gives today's chart.

  A spec does not hold the chart's data: it names it (`"data" =>
  "sales"`), and the chart gets it when it draws. `dump(chart, data:
  true)` puts the data in (`"datasets"`), for a file that stands alone.

  ## The shape

  A chart of one layer has its kind, channels and options at the top:

      %{
        "fude" => 1,
        "kind" => "line",
        "title" => "Visits",
        "x" => %{"field" => "day", "time" => "week"},
        "y" => "count",
        "color" => "source",
        "curve" => "monotone"
      }

  A chart of several layers has them in `"layers"`, each with its kind,
  channels and options:

      %{"fude" => 1, "layers" => [%{"kind" => "area", ...}, %{"kind" => "rule", "y" => 1000}]}

  A layer, and an annotation, may have an `"id"`, text that names it
  among the others: a chart shared with `Fude.Issho` gives each one, so
  that two people who change two layers at once both have their change.

  A channel is a field's name, or a map of the keys of `Fude.Channel`
  (`"format" => "currency:EUR"` for `{:currency, "EUR"}`); a constant is
  `%{"value" => 1000}`.

  ## Errors

  `load/1` checks the whole spec and gives every error, each with where it
  is and what to do:

      {:error, [%{path: ["y", "aggregate"], message: ~s|must be one of "count", "sum", ...; did you mean "sum"?|}]}
  """

  alias Fude.{Channel, Chart, Layer}

  @version 1

  @typedoc "A spec: a map with string keys and JSON values."
  @type t :: %{String.t() => term()}

  @typedoc "An error of a spec: where (a path of keys and indexes), and what is wrong."
  @type error :: %{path: [String.t() | non_neg_integer()], message: String.t()}

  @doc "The version of the specs that `dump/1` gives."
  @spec version() :: pos_integer()
  def version, do: @version

  @doc """
  The chart as a spec. With `data: true`, the spec holds the chart's data
  too, under `"datasets"`, as `Fude.Data` normalizes it. With `layers:
  true`, a chart of one layer has it in `"layers"` too, as a chart of
  several does.
  """
  @spec dump(Chart.t(), keyword()) :: t()
  def dump(%Chart{} = chart, opts \\ []) do
    head =
      %{"fude" => @version}
      |> put_words(chart)
      |> put_unless("data", chart.data, "data")
      |> put_unless("height", chart.height, nil)
      |> put_unless("annotations", Enum.map(chart.annotations, &Fude.Annotation.dump/1), [])
      |> put_unless("facet", dump_facet(chart.facet), nil)

    spec =
      case {chart.layers, opts[:layers]} do
        {[layer], layers?} when layers? != true -> Map.merge(head, dump_layer(layer))
        {layers, _layers?} -> Map.put(head, "layers", Enum.map(layers, &dump_layer/1))
      end

    if opts[:data] && chart.datasets != %{} do
      Map.put(
        spec,
        "datasets",
        Map.new(chart.datasets, fn {name, data} -> {name, Fude.Data.rows(data)} end)
      )
    else
      spec
    end
  end

  defp put_words(spec, chart) do
    Enum.reduce(Chart.words(), spec, fn key, spec ->
      put_unless(spec, Atom.to_string(key), Map.get(chart, key), nil)
    end)
  end

  defp dump_facet(nil), do: nil
  defp dump_facet(%{field: field, columns: nil}), do: %{"field" => field}

  defp dump_facet(%{field: field, columns: columns}),
    do: %{"field" => field, "columns" => columns}

  defp put_unless(map, _key, value, value), do: map
  defp put_unless(map, key, value, _default), do: Map.put(map, key, value)

  defp dump_layer(%Layer{id: id, kind: kind, channels: channels, options: options}) do
    channels =
      Map.new(channels, fn
        {:tooltip, list} -> {"tooltip", Enum.map(list, &dump_channel/1)}
        {name, channel} -> {Atom.to_string(name), dump_channel(channel)}
      end)

    options = Map.new(options, fn {key, value} -> {Atom.to_string(key), dump_value(value)} end)

    %{"kind" => Atom.to_string(kind)}
    |> put_unless("id", id, nil)
    |> Map.merge(channels)
    |> Map.merge(options)
  end

  defp dump_channel(%Channel{field: field} = channel) when is_binary(field) do
    if channel == %Channel{field: field}, do: field, else: dump_full(channel)
  end

  defp dump_channel(channel), do: dump_full(channel)

  defp dump_full(channel) do
    channel
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn
      {:format, {:currency, code}} ->
        {"format", "currency:" <> code}

      {:bin, %{} = bin} ->
        {"bin", Map.new(bin, fn {k, v} -> {Atom.to_string(k), v} end)}

      {:scale, scale} ->
        {"scale", Map.new(scale, fn {k, v} -> {Atom.to_string(k), dump_value(v)} end)}

      {:sort, sort} when is_list(sort) ->
        {"sort", sort}

      {key, value} ->
        {Atom.to_string(key), dump_value(value)}
    end)
  end

  defp dump_value(value) when is_boolean(value) or is_nil(value), do: value
  defp dump_value(value) when is_atom(value), do: Atom.to_string(value)
  defp dump_value(value), do: value

  @doc """
  The chart of a spec, or every error of it. A spec of an earlier version
  is first migrated to this one.
  """
  @spec load(t()) :: {:ok, Chart.t()} | {:error, [error()]}
  def load(spec) when is_map(spec) do
    with {:ok, spec} <- migrate(spec) do
      {chart, errors} = load_chart(spec)

      case errors do
        [] -> {:ok, chart}
        errors -> {:error, Enum.reverse(errors)}
      end
    end
  end

  def load(other), do: {:error, [%{path: [], message: "a spec is a map, got: #{inspect(other)}"}]}

  @doc "The chart of a spec; raises an `ArgumentError` with every error."
  @spec load!(t()) :: Chart.t()
  def load!(spec) do
    case load(spec) do
      {:ok, chart} ->
        chart

      {:error, errors} ->
        raise ArgumentError, "Fude: the spec is not valid:\n" <> format_errors(errors)
    end
  end

  @doc "The errors as lines of text, one for each: `y.aggregate: must be ...`."
  @spec format_errors([error()]) :: String.t()
  def format_errors(errors) do
    Enum.map_join(errors, "\n", fn
      %{path: [], message: message} -> "  " <> message
      %{path: path, message: message} -> "  " <> Enum.join(path, ".") <> ": " <> message
    end)
  end

  # The specs of each earlier version are migrated forward, one version at
  # a time. Version 1 is the first: there is nothing to migrate yet.
  defp migrate(%{"fude" => @version} = spec), do: {:ok, spec}

  defp migrate(%{"fude" => version}) when is_integer(version) and version > @version do
    {:error,
     [%{path: ["fude"], message: "is version #{version}, newer than this Fude's (#{@version})"}]}
  end

  defp migrate(%{"fude" => version}) do
    {:error,
     [%{path: ["fude"], message: "must be a version of the spec, got: #{inspect(version)}"}]}
  end

  defp migrate(_spec) do
    {:error,
     [%{path: ["fude"], message: "is missing: a Fude spec carries its version, \"fude\" => 1"}]}
  end

  @chart_keys ~w(fude title subtitle caption source description data height layers datasets annotations facet)

  defp load_chart(spec) do
    acc = {%Chart{}, []}

    acc =
      Enum.reduce(spec, acc, fn
        {"fude", _}, acc ->
          acc

        {"layers", _}, acc ->
          acc

        {"datasets", datasets}, acc ->
          load_datasets(datasets, acc)

        {key, value}, acc when key in ~w(title subtitle caption source description) ->
          word(key, value, acc)

        {"data", name}, acc ->
          data_name(name, acc)

        {"height", height}, acc ->
          height(height, acc)

        {"annotations", list}, acc ->
          annotations(list, acc)

        {"facet", facet}, acc ->
          facet(facet, acc)

        _other, acc ->
          acc
      end)

    case spec do
      %{"layers" => layers} when is_list(layers) and layers != [] ->
        layers
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {layer, index}, acc -> add_layer(layer, ["layers", index], acc) end)
        |> unknown_at_top(spec, @chart_keys)

      %{"layers" => _} ->
        error(acc, ["layers"], "must be a list of one or more layers")

      %{"kind" => _} ->
        top = Map.drop(spec, @chart_keys)
        add_layer(top, [], acc)

      _ ->
        error(acc, [], "has no \"kind\" and no \"layers\": say what the chart draws")
    end
  end

  defp unknown_at_top({chart, errors}, spec, keys) do
    Enum.reduce(Map.keys(spec) -- keys, {chart, errors}, fn key, acc ->
      error(acc, [key], "is not a key of a chart of layers" <> Fude.Names.suggest(key, keys))
    end)
  end

  defp word(key, value, {chart, errors}) when is_binary(value) or is_nil(value),
    do: {Map.put(chart, String.to_existing_atom(key), value), errors}

  defp word(key, value, acc), do: error(acc, [key], "must be text, got: #{inspect(value)}")

  defp data_name(name, {chart, errors}) when is_binary(name) and name != "",
    do: {%{chart | data: name}, errors}

  defp data_name(name, acc),
    do: error(acc, ["data"], "must be the name of the data, got: #{inspect(name)}")

  defp height(height, {chart, errors}) when is_integer(height) and height > 0,
    do: {%{chart | height: height}, errors}

  defp height(height, acc),
    do: error(acc, ["height"], "must be a whole number of pixels, got: #{inspect(height)}")

  defp facet(%{"field" => field} = facet, {chart, errors})
       when is_binary(field) and field != "" do
    case facet["columns"] do
      nil ->
        {%{chart | facet: %{field: field, columns: nil}}, errors}

      n when is_integer(n) and n > 0 ->
        {%{chart | facet: %{field: field, columns: n}}, errors}

      n ->
        error({chart, errors}, ["facet", "columns"], "must be a whole number, got: #{inspect(n)}")
    end
  end

  defp facet(other, acc),
    do: error(acc, ["facet"], ~s|must be {"field": name}, with "columns", got: #{inspect(other)}|)

  defp annotations(list, acc) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {map, index}, {chart, errors} ->
      case Fude.Annotation.load(map) do
        {:ok, annotation} -> {%{chart | annotations: chart.annotations ++ [annotation]}, errors}
        {:error, message} -> error({chart, errors}, ["annotations", index], message)
      end
    end)
  end

  defp annotations(other, acc),
    do: error(acc, ["annotations"], "must be a list of annotations, got: #{inspect(other)}")

  defp load_datasets(datasets, {chart, errors}) when is_map(datasets) do
    {%{chart | datasets: Map.merge(chart.datasets, datasets)}, errors}
  end

  defp load_datasets(other, acc),
    do: error(acc, ["datasets"], "must be a map of names to rows, got: #{inspect(other)}")

  @kind_names Map.new(Layer.kinds(), &{Atom.to_string(&1), &1})

  defp add_layer(layer, path, {chart, errors}) when is_map(layer) do
    case Map.fetch(layer, "kind") do
      {:ok, name} when is_map_key(@kind_names, name) ->
        kind = Map.fetch!(@kind_names, name)
        {layer_struct, errors} = load_layer(kind, Map.delete(layer, "kind"), path, errors)
        {%{chart | layers: chart.layers ++ [layer_struct]}, errors}

      {:ok, name} ->
        message =
          "must be a kind of chart, got: #{inspect(name)}" <>
            Fude.Names.suggest(to_string(name), Map.keys(@kind_names))

        error({chart, errors}, path ++ ["kind"], message)

      :error ->
        error({chart, errors}, path, "has no \"kind\"")
    end
  end

  defp add_layer(other, path, acc), do: error(acc, path, "must be a map, got: #{inspect(other)}")

  defp load_layer(kind, map, path, errors) do
    spec = Layer.kind_spec(kind)

    keys = %{
      kind: kind,
      path: path,
      channels: Map.new(spec.channels, &{Atom.to_string(&1), &1}),
      options: Map.new(spec.options, fn {key, check} -> {Atom.to_string(key), {key, check}} end)
    }

    {layer, errors} = Enum.reduce(map, {%Layer{kind: kind}, errors}, &load_key(&1, &2, keys))

    # A channel that is there with an error is not missing too.
    given = map |> Map.keys() |> MapSet.new()

    errors =
      spec.needs
      |> Enum.reject(&(Map.has_key?(layer.channels, &1) or Atom.to_string(&1) in given))
      |> Enum.reduce(errors, fn name, errors ->
        [
          %{path: path ++ [Atom.to_string(name)], message: "is missing: a #{kind} chart needs it"}
          | errors
        ]
      end)

    {layer, errors}
  end

  # A key of a layer: its id, a channel, an option, or an error.
  defp load_key({"id", id}, {layer, errors}, _keys) when is_binary(id) and id != "",
    do: {%{layer | id: id}, errors}

  defp load_key({"id", id}, {layer, errors}, keys),
    do:
      {layer,
       [%{path: keys.path ++ ["id"], message: "must be text, got: #{inspect(id)}"} | errors]}

  defp load_key({"tooltip", value}, {layer, errors}, %{channels: %{"tooltip" => _}} = keys),
    do: load_tooltip(value, keys.path ++ ["tooltip"], layer, errors)

  defp load_key({key, value}, {layer, errors}, %{channels: channels} = keys)
       when is_map_key(channels, key) do
    case load_channel(value, keys.path ++ [key]) do
      {:ok, channel} ->
        {%{layer | channels: Map.put(layer.channels, channels[key], channel)}, errors}

      {:error, more} ->
        {layer, more ++ errors}
    end
  end

  defp load_key({key, value}, {layer, errors}, %{options: options} = keys)
       when is_map_key(options, key) do
    {atom, check} = options[key]

    case load_option(check, value) do
      {:ok, value} ->
        {%{layer | options: Map.put(layer.options, atom, value)}, errors}

      :error ->
        message = "must be #{Layer.describe(check)}, got: #{inspect(value)}"
        {layer, [%{path: keys.path ++ [key], message: message} | errors]}
    end
  end

  defp load_key({key, _value}, {layer, errors}, keys) do
    names = Map.keys(keys.channels) ++ Map.keys(keys.options)

    message =
      "is not a key of a #{keys.kind} chart; it takes #{Enum.join(names, ", ")}" <>
        Fude.Names.suggest(key, names)

    {layer, [%{path: keys.path ++ [key], message: message} | errors]}
  end

  defp load_option({:in, values} = check, value) when is_binary(value) do
    case Enum.find(values, &(Atom.to_string(&1) == value)) do
      nil -> if Layer.check_option(check, value), do: {:ok, value}, else: :error
      atom -> {:ok, atom}
    end
  end

  defp load_option(check, value),
    do: if(Layer.check_option(check, value), do: {:ok, value}, else: :error)

  defp load_tooltip(list, path, layer, errors) when is_list(list) do
    {channels, errors} =
      list
      |> Enum.with_index()
      |> Enum.reduce({[], errors}, fn {value, index}, {channels, errors} ->
        case load_channel(value, path ++ [index]) do
          {:ok, channel} -> {[channel | channels], errors}
          {:error, more} -> {channels, more ++ errors}
        end
      end)

    {%{layer | channels: Map.put(layer.channels, :tooltip, Enum.reverse(channels))}, errors}
  end

  defp load_tooltip(other, path, layer, errors),
    do:
      {layer,
       [%{path: path, message: "must be a list of channels, got: #{inspect(other)}"} | errors]}

  @doc false
  # A channel of a spec: a field's name, or a map.
  def load_channel(field, _path) when is_binary(field) and field != "",
    do: {:ok, %Channel{field: field}}

  def load_channel(map, path) when is_map(map) do
    {channel, errors} =
      Enum.reduce(map, {%Channel{}, []}, fn {key, value}, {channel, errors} ->
        case channel_key(key, value) do
          {:ok, atom, value} -> {Map.put(channel, atom, value), errors}
          {:error, message} -> {channel, [%{path: path ++ [key], message: message} | errors]}
        end
      end)

    errors =
      if is_nil(channel.field) and is_nil(channel.value) and channel.aggregate != :count and
           errors == [],
         do: [%{path: path, message: "needs a \"field\" or a \"value\""}],
         else: errors

    if errors == [], do: {:ok, channel}, else: {:error, errors}
  end

  def load_channel(other, path),
    do:
      {:error,
       [%{path: path, message: "must be a field's name or a map, got: #{inspect(other)}"}]}

  defp channel_key("field", field) when is_binary(field) and field != "", do: {:ok, :field, field}
  defp channel_key("value", value), do: {:ok, :value, value}

  defp channel_key("title", title) when is_binary(title) or title == false,
    do: {:ok, :title, title}

  defp channel_key("type", type), do: atom(:type, type, Channel.types())
  defp channel_key("aggregate", aggregate), do: atom(:aggregate, aggregate, Channel.aggregates())
  defp channel_key("time", unit), do: atom(:time, unit, Channel.time_units())
  defp channel_key("stack", false), do: {:ok, :stack, false}
  defp channel_key("stack", stack), do: atom(:stack, stack, Channel.stacks())
  defp channel_key("sort", sort) when is_list(sort), do: {:ok, :sort, sort}
  defp channel_key("sort", sort), do: atom(:sort, sort, Channel.sorts())
  defp channel_key("bin", bin) when is_boolean(bin), do: {:ok, :bin, bin}

  defp channel_key("bin", %{"count" => count}) when is_integer(count) and count > 0,
    do: {:ok, :bin, %{count: count}}

  defp channel_key("bin", %{"step" => step}) when is_number(step) and step > 0,
    do: {:ok, :bin, %{step: step}}

  defp channel_key("bin", bin),
    do: {:error, "must be true, or {\"count\": n} or {\"step\": n}, got: #{inspect(bin)}"}

  defp channel_key("format", "currency:" <> code) when byte_size(code) == 3,
    do: {:ok, :format, {:currency, code}}

  defp channel_key("format", format), do: atom(:format, format, Channel.formats())
  defp channel_key("digits", digits) when digits in 0..20, do: {:ok, :digits, digits}

  defp channel_key("digits", digits),
    do: {:error, "must be a whole number from 0 to 20, got: #{inspect(digits)}"}

  defp channel_key("scheme", scheme) when is_list(scheme) do
    if Channel.colors?(scheme),
      do: {:ok, :scheme, scheme},
      else:
        {:error, "must be a list of two colors or more (\"#0b6e4f\"), got: #{inspect(scheme)}"}
  end

  defp channel_key("scheme", scheme), do: atom(:scheme, scheme, Channel.schemes())
  defp channel_key("mid", mid) when is_number(mid), do: {:ok, :mid, mid}
  defp channel_key("mid", mid), do: {:error, "must be a number, got: #{inspect(mid)}"}
  defp channel_key("axis", axis), do: atom(:axis, axis, Channel.axes())
  defp channel_key("scale", scale) when is_map(scale), do: scale(scale)
  defp channel_key("scale", scale), do: {:error, "must be a map, got: #{inspect(scale)}"}

  defp channel_key(key, _value) do
    keys =
      ~w(field type aggregate time bin sort format digits scheme mid title scale stack value axis)

    {:error, "is not a key of a channel" <> Fude.Names.suggest(key, keys)}
  end

  defp scale(map) do
    Enum.reduce_while(map, {:ok, :scale, %{}}, fn {key, value}, {:ok, :scale, scale} ->
      result =
        case {key, value} do
          {"type", type} ->
            atom(:type, type, Channel.scale_types())

          {"domain", domain} when is_list(domain) ->
            {:ok, :domain, domain}

          {"zero", zero} when is_boolean(zero) ->
            {:ok, :zero, zero}

          {"nice", nice} when is_boolean(nice) ->
            {:ok, :nice, nice}

          {key, value} ->
            {:error, "has #{inspect(key)} = #{inspect(value)}, which is not a key of a scale"}
        end

      case result do
        {:ok, atom, value} -> {:cont, {:ok, :scale, Map.put(scale, atom, value)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp atom(key, value, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> {:error, must_be(allowed, value)}
      atom -> {:ok, key, atom}
    end
  end

  defp atom(_key, value, allowed), do: {:error, must_be(allowed, value)}

  defp must_be(allowed, value) do
    names = Enum.map(allowed, &Atom.to_string/1)

    "must be one of #{Enum.map_join(names, ", ", &inspect/1)}, got: #{inspect(value)}" <>
      if(is_binary(value), do: Fude.Names.suggest(value, names), else: "")
  end

  defp error({chart, errors}, path, message),
    do: {chart, [%{path: path, message: message} | errors]}
end
