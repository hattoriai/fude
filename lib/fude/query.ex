if Code.ensure_loaded?(Ecto.Query) do
  defmodule Fude.Query do
    @moduledoc """
    A chart's data from an Ecto query, grouped and aggregated in the
    database: a chart of fifty million rows reads a few hundred.

        Fude.bar(Fude.query(Order, Repo), x: :status, y: {:count, :id})

        from(o in Order, where: o.shop_id == ^shop.id)
        |> Fude.query(Repo)
        |> Fude.line(x: {:month, :inserted_at}, y: {:sum, :total}, color: :channel)

    For each layer, one `GROUP BY` query reads the channels that are not
    aggregated (a field, its unit of time, its bin) and the aggregates of
    the others (`count`, `sum`, `mean`, `min`, `max`, `distinct`). A
    histogram reads the least and the greatest value first, for its bins.
    PostgreSQL, MySQL and SQLite run them, each with its own functions of
    dates.

    A layer with no aggregate (a scatter of points), a `median`, or small
    multiples read the rows' fields instead, only those the chart draws,
    at most `:limit` rows.

    The query may have its own `where`, `join` and `order_by`; the order
    is dropped for the groups. Masu's grids give their filtered rows as a
    query (`Masu.Live.selected/1`): a chart of what a grid shows.

    ## Options

      * `:repo_opts` - options for each call to the repo, such as `prefix:`.
      * `:limit` - the most rows read when they are read as they are;
        100,000 when not given.
    """

    import Ecto.Query

    alias Fude.{Channel, Data}

    @compile {:no_warn_undefined, [Decimal]}

    @type t :: %__MODULE__{
            query: Ecto.Query.t(),
            repo: module(),
            repo_opts: keyword(),
            limit: pos_integer()
          }

    defstruct [:query, :repo, repo_opts: [], limit: 100_000]

    @doc "The data of an Ecto query or schema, read by `repo`."
    @spec new(Ecto.Queryable.t(), module(), keyword()) :: t()
    def new(queryable, repo, opts \\ []) when is_atom(repo) do
      %__MODULE__{
        query: queryable |> Ecto.Queryable.to_query() |> exclude(:order_by) |> exclude(:select),
        repo: repo,
        repo_opts: Keyword.get(opts, :repo_opts, []),
        limit: Keyword.get(opts, :limit, 100_000)
      }
    end

    @doc false
    # The fields of the query's first source, when it is a schema: what the
    # chart's fields are checked against. Nil for a table by its name.
    @spec names(t()) :: [String.t()] | nil
    def names(%__MODULE__{query: %{from: %{source: {_table, schema}}}})
        when is_atom(schema) and not is_nil(schema) do
      if function_exported?(schema, :__schema__, 1),
        do: Enum.map(schema.__schema__(:fields), &Atom.to_string/1)
    end

    def names(_source), do: nil

    @doc false
    # Whether a field of the query's schema is a number, which a value
    # channel sums; a field of a table by its name is taken as one.
    @spec number?(t(), String.t()) :: boolean()
    def number?(%__MODULE__{query: %{from: %{source: {_table, schema}}}}, field)
        when is_atom(schema) and not is_nil(schema) and is_binary(field) do
      with true <- function_exported?(schema, :__schema__, 2),
           atom when not is_nil(atom) <-
             Enum.find(schema.__schema__(:fields), &(Atom.to_string(&1) == field)) do
        schema.__schema__(:type, atom) in [:integer, :float, :decimal, :id]
      else
        _ -> true
      end
    end

    def number?(_source, _field), do: true

    @doc false
    # Whether the database can do a layer's work: every aggregate is one
    # that SQL has.
    @spec pushable?(map()) :: boolean()
    def pushable?(aggregated),
      do: aggregated != %{} and Enum.all?(aggregated, fn {_name, fun} -> fun != :median end)

    @doc false
    # The rows of a layer, grouped and aggregated by the database, as
    # Fude.Compile has them (a map by channel), with the bins of its binned
    # channels, and the data of the rows for the types of the fields.
    @spec rows(t(), [{atom(), Channel.t()}], %{atom() => atom()}, (number(), number(), term() ->
                                                                     term())) ::
            {[map()], map(), Data.t()}
    def rows(%__MODULE__{} = source, channels, aggregated, bins_for) do
      adapter = source.repo.__adapter__()
      bins = bins(source, channels, bins_for)

      # Constants (a rule at y: 1000) are not the database's: they are put
      # in each row after.
      {constants, read} =
        Enum.split_with(channels, fn {name, c} ->
          is_nil(c.field) and not Map.has_key?(aggregated, name)
        end)

      keys = for {name, _channel} <- read, not Map.has_key?(aggregated, name), do: name

      # The keys made in a subquery, as columns of their own, and grouped
      # in the query around it: a database groups by a column, where it
      # may not see that two expressions with parameters are the same.
      inner =
        Map.new(read, fn {name, channel} ->
          case aggregated do
            %{^name => _fun} -> {name, raw(channel)}
            _ -> {name, key(channel, bins[name], adapter)}
          end
        end)

      columns = Enum.map(keys, &dynamic([s], field(s, ^&1)))

      outer =
        Map.new(read, fn {name, channel} ->
          case aggregated do
            %{^name => fun} -> {name, aggregate(fun, channel, name)}
            _ -> {name, dynamic([s], field(s, ^name))}
          end
        end)

      # The groups in the order of their keys: the same chart every time.
      query =
        from(s in subquery(select(source.query, ^inner)))
        |> group_by(^columns)
        |> order_by(^columns)
        |> select(^outer)

      constant = Map.new(constants, fn {name, channel} -> {name, channel.value} end)

      rows =
        query
        |> source.repo.all(source.repo_opts)
        |> Enum.map(&(&1 |> coerce(read, bins) |> Map.merge(constant)))

      # The types from the values as the database gave them (a date is a
      # time); then each time in milliseconds, as Fude.Compile has them.
      data = types(rows, channels)
      {Enum.map(rows, &milliseconds/1), bins, data}
    end

    @doc false
    # The rows of the query as they are: the fields the chart reads.
    @spec data(t(), [String.t()]) :: Data.t()
    def data(%__MODULE__{} = source, fields) do
      select = Map.new(fields, fn name -> {name, dynamic([r], field(r, ^atom!(name)))} end)

      source.query
      |> limit(^source.limit)
      |> select(^select)
      |> source.repo.all(source.repo_opts)
      |> Data.new(fields)
    end

    # The bins of the binned channels: the least and the greatest value of
    # each, read first.
    defp bins(source, channels, bins_for) do
      for {name, %Channel{bin: bin, field: field}} <- channels, bin, into: %{} do
        column = atom!(field)

        %{min: min, max: max} =
          source.query
          |> select([r], %{min: min(field(r, ^column)), max: max(field(r, ^column))})
          |> source.repo.one(source.repo_opts)

        {name, if(is_nil(min), do: {0.0, 1.0, 1}, else: bins_for.(number(min), number(max), bin))}
      end
    end

    # A channel that groups: its field, its unit of time, or its bin.
    defp key(%Channel{field: field, time: nil}, nil, _adapter),
      do: dynamic([r], field(r, ^atom!(field)))

    defp key(%Channel{field: field}, {start, step, _n}, adapter) do
      column = atom!(field)

      if adapter == Ecto.Adapters.SQLite3,
        do:
          dynamic([r], fragment("CAST((? - ?) / ? AS INTEGER)", field(r, ^column), ^start, ^step)),
        else: dynamic([r], fragment("FLOOR((? - ?) / ?)", field(r, ^column), ^start, ^step))
    end

    defp key(%Channel{field: field, time: unit}, nil, adapter),
      do: truncate(atom!(field), unit, adapter)

    # The start of a unit of time, in each database's words. A week starts
    # on Monday, as in Fude.Rules.
    defp truncate(column, unit, Ecto.Adapters.Postgres),
      do: dynamic([r], fragment("date_trunc(?, ?)", ^Atom.to_string(unit), field(r, ^column)))

    defp truncate(column, unit, Ecto.Adapters.MyXQL) do
      case unit do
        :minute ->
          dynamic([r], fragment("DATE_FORMAT(?, '%Y-%m-%d %H:%i:00')", field(r, ^column)))

        :hour ->
          dynamic([r], fragment("DATE_FORMAT(?, '%Y-%m-%d %H:00:00')", field(r, ^column)))

        :day ->
          dynamic([r], fragment("DATE(?)", field(r, ^column)))

        :week ->
          dynamic(
            [r],
            fragment(
              "DATE_SUB(DATE(?), INTERVAL WEEKDAY(?) DAY)",
              field(r, ^column),
              field(r, ^column)
            )
          )

        :month ->
          dynamic([r], fragment("DATE_FORMAT(?, '%Y-%m-01')", field(r, ^column)))

        :quarter ->
          dynamic(
            [r],
            fragment(
              "MAKEDATE(YEAR(?), 1) + INTERVAL (QUARTER(?) - 1) QUARTER",
              field(r, ^column),
              field(r, ^column)
            )
          )

        :year ->
          dynamic([r], fragment("DATE_FORMAT(?, '%Y-01-01')", field(r, ^column)))
      end
    end

    defp truncate(column, unit, _sqlite) do
      case unit do
        :minute ->
          dynamic([r], fragment("strftime('%Y-%m-%d %H:%M:00', ?)", field(r, ^column)))

        :hour ->
          dynamic([r], fragment("strftime('%Y-%m-%d %H:00:00', ?)", field(r, ^column)))

        :day ->
          dynamic([r], fragment("date(?)", field(r, ^column)))

        :week ->
          dynamic([r], fragment("date(?, 'weekday 0', '-6 days')", field(r, ^column)))

        :month ->
          dynamic([r], fragment("strftime('%Y-%m-01', ?)", field(r, ^column)))

        :quarter ->
          dynamic(
            [r],
            fragment(
              "printf('%s-%02d-01', strftime('%Y', ?), ((CAST(strftime('%m', ?) AS INTEGER) - 1) / 3) * 3 + 1)",
              field(r, ^column),
              field(r, ^column)
            )
          )

        :year ->
          dynamic([r], fragment("strftime('%Y-01-01', ?)", field(r, ^column)))
      end
    end

    # A channel to aggregate, as the subquery gives it: its field, or a 1
    # to count rows.
    defp raw(%Channel{field: nil}), do: dynamic(fragment("1"))
    defp raw(%Channel{field: field}), do: dynamic([r], field(r, ^atom!(field)))

    defp aggregate(:count, %Channel{field: nil}, _name), do: dynamic(count())
    defp aggregate(:count, _channel, name), do: dynamic([s], count(field(s, ^name)))
    defp aggregate(:distinct, _channel, name), do: dynamic([s], count(field(s, ^name), :distinct))
    defp aggregate(:sum, _channel, name), do: dynamic([s], sum(field(s, ^name)))
    # A mean of floating-point numbers: MySQL's mean of whole numbers is a
    # decimal of four places.
    defp aggregate(:mean, _channel, name),
      do: dynamic([s], avg(fragment("? * 1e0", field(s, ^name))))

    defp aggregate(:min, _channel, name), do: dynamic([s], min(field(s, ^name)))
    defp aggregate(:max, _channel, name), do: dynamic([s], max(field(s, ^name)))

    # A row of the database as Fude.Compile has its rows: a decimal a
    # number, a unit of time a time (MySQL and SQLite give its text), a bin
    # its index, the greatest value in the last bin.
    defp coerce(row, channels, bins) do
      Map.new(channels, fn {name, channel} -> {name, value(row[name], channel, bins[name])} end)
    end

    defp value(nil, _channel, _bin), do: nil
    defp value(value, %Channel{time: unit}, nil) when not is_nil(unit), do: time(value)

    defp value(value, _channel, {_start, _step, n}),
      do: value |> number() |> trunc() |> min(n - 1) |> max(0)

    defp value(value, _channel, nil), do: number(value)

    defp time(%Date{} = date), do: date
    defp time(%NaiveDateTime{} = time), do: time
    defp time(%DateTime{} = time), do: time

    defp time(text) when is_binary(text) do
      with {:error, _} <- NaiveDateTime.from_iso8601(text),
           {:error, _} <- Date.from_iso8601(text) do
        text
      else
        {:ok, time} -> time
      end
    end

    defp milliseconds(row) do
      Map.new(row, fn
        {name, %Date{} = value} -> {name, Data.value(value, :time)}
        {name, %NaiveDateTime{} = value} -> {name, Data.value(value, :time)}
        {name, %DateTime{} = value} -> {name, Data.value(value, :time)}
        pair -> pair
      end)
    end

    defp number(%{__struct__: Decimal} = value), do: Decimal.to_float(value)
    defp number(value) when is_number(value), do: value
    defp number(value), do: value

    # The data of the grouped rows, by the fields of their channels: for the
    # types of the fields (a time, a number, a category).
    defp types(rows, channels) do
      rows
      |> Enum.map(fn row ->
        for {name, %Channel{field: field}} <- channels,
            is_binary(field),
            into: %{},
            do: {field, row[name]}
      end)
      |> Data.new()
    end

    defp atom!(field) do
      String.to_existing_atom(field)
    rescue
      ArgumentError ->
        reraise ArgumentError,
                [message: "Fude: the field #{inspect(field)} is not in the query"],
                __STACKTRACE__
    end
  end
end
