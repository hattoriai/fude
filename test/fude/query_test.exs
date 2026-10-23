defmodule Fude.QueryTest do
  # One database for the module: SQLite, or PostgreSQL with
  # FUDE_DB=postgres (a server on localhost, user postgres, password
  # postgres), or MySQL with FUDE_DB=mysql (user root, password mysql), as
  # in docker-compose.yml and CI.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Fude.Compile
  alias FudeTest.Order

  @db System.get_env("FUDE_DB", "sqlite")
  @repo %{"postgres" => FudeTest.PostgresRepo, "mysql" => FudeTest.MySQLRepo}[@db] ||
          FudeTest.SQLiteRepo

  setup_all do
    {pid, cleanup} = start_repo(@db)

    orders =
      for i <- 1..400 do
        day = Date.add(~D[2026-01-01], rem(i * 7, 120))

        %{
          id: i,
          status: Enum.at(~w(delivered shipped returned), rem(i, 3)),
          channel: Enum.at(~w(online retail), rem(i, 2)),
          total: 10.0 + rem(i * 37, 490),
          items: 1 + rem(i, 5),
          placed_on: day,
          placed_at: DateTime.new!(day, Time.new!(rem(i, 24), 0, 0), "Etc/UTC")
        }
      end

    @repo.insert_all(Order, orders)

    on_exit(fn ->
      Process.exit(pid, :normal)
      cleanup.()
    end)

    %{orders: orders}
  end

  defp start_repo("mysql") do
    database = "fude_test_#{System.unique_integer([:positive])}"
    opts = [hostname: "localhost", username: "root", password: "mysql"]
    {:ok, admin} = MyXQL.start_link(opts)
    MyXQL.query!(admin, "CREATE DATABASE #{database}")
    GenServer.stop(admin)
    {:ok, pid} = @repo.start_link(opts ++ [database: database, pool_size: 1])

    @repo.query!("""
    CREATE TABLE orders (
      id INTEGER PRIMARY KEY, status TEXT, channel TEXT, total DOUBLE, items INTEGER,
      placed_on DATE, placed_at DATETIME
    )
    """)

    drop = fn ->
      {:ok, admin} = MyXQL.start_link(opts)
      MyXQL.query!(admin, "DROP DATABASE IF EXISTS #{database}")
      GenServer.stop(admin)
    end

    {pid, drop}
  end

  defp start_repo("sqlite") do
    path = Path.join(System.tmp_dir!(), "fude-sqlite-#{System.unique_integer([:positive])}.db")
    {:ok, pid} = @repo.start_link(database: path, pool_size: 1)

    @repo.query!("""
    CREATE TABLE orders (
      id INTEGER PRIMARY KEY, status TEXT, channel TEXT, total REAL, items INTEGER,
      placed_on TEXT, placed_at TEXT
    )
    """)

    {pid, fn -> File.rm(path) end}
  end

  defp start_repo("postgres") do
    database = "fude_test_#{System.unique_integer([:positive])}"
    opts = [hostname: "localhost", username: "postgres", password: "postgres"]
    {:ok, admin} = Postgrex.start_link(opts ++ [database: "postgres"])
    Postgrex.query!(admin, "CREATE DATABASE #{database}", [])
    {:ok, pid} = @repo.start_link(opts ++ [database: database, pool_size: 1])

    @repo.query!("""
    CREATE TABLE orders (
      id INTEGER PRIMARY KEY, status TEXT, channel TEXT, total DOUBLE PRECISION, items INTEGER,
      placed_on DATE, placed_at TIMESTAMP(0)
    )
    """)

    GenServer.stop(admin)

    # The cleanup runs in a process of its own: a connection of its own.
    drop = fn ->
      {:ok, admin} = Postgrex.start_link(opts ++ [database: "postgres"])
      Postgrex.query!(admin, "DROP DATABASE IF EXISTS #{database} WITH (FORCE)", [])
      GenServer.stop(admin)
    end

    {pid, drop}
  end

  defp compile!(chart) do
    {:ok, wire} = Compile.compile(chart)
    wire
  end

  # The same chart of the rows in memory: what the database must give.
  defp in_memory(chart, orders), do: compile!(Fude.put_data(chart, orders))

  test "counts and sums by category in the database, as in memory", %{orders: orders} do
    chart = Fude.bar(x: :status, y: {:sum, :total}, color: :channel)
    from_db = chart |> Fude.put_data(Fude.query(Order, @repo)) |> compile!()

    assert Compile.table(from_db) |> elem(1) |> Enum.sort() ==
             Compile.table(in_memory(chart, orders)) |> elem(1) |> Enum.sort()
  end

  test "takes a unit of time in the database: a month of a date, a week of a time", %{
    orders: orders
  } do
    for chart <- [
          Fude.line(x: {:month, :placed_on}, y: {:count, :id}),
          Fude.line(x: {:week, :placed_at}, y: {:mean, :items}),
          Fude.bar(x: {:quarter, :placed_on}, y: {:max, :total}),
          Fude.bar(x: {:day, :placed_at}, y: {:min, :total})
        ] do
      from_db = chart |> Fude.put_data(Fude.query(Order, @repo)) |> compile!()
      memory = in_memory(chart, orders)
      assert Compile.table(from_db) == Compile.table(memory), inspect(chart.layers)
    end
  end

  test "puts numbers in bins in the database", %{orders: orders} do
    chart = Fude.histogram(x: :total, bins: 10)
    from_db = chart |> Fude.put_data(Fude.query(Order, @repo)) |> compile!()
    assert from_db["scales"]["x"]["bins"] == in_memory(chart, orders)["scales"]["x"]["bins"]
    assert Compile.table(from_db) == Compile.table(in_memory(chart, orders))
  end

  test "keeps the query's own where" do
    query = from(o in Order, where: o.status == "returned")
    wire = Fude.bar(query |> Fude.query(@repo), x: :status, y: {:count, :id}) |> compile!()
    assert {_, [["returned", 133]]} = Compile.table(wire)
  end

  test "reads the fields of a scatter as they are, at most the limit" do
    wire =
      Fude.scatter(Fude.query(Order, @repo, limit: 50), x: :items, y: :total) |> compile!()

    assert hd(wire["layers"])["n"] == 50
  end

  test "a field that is not in the schema is an error with a suggestion" do
    assert {:error, [message]} =
             Compile.compile(Fude.bar(Fude.query(Order, @repo), x: :stauts, y: {:count, :id}))

    assert message =~ ~s|did you mean "status"?|
  end
end
