defmodule FudeTest.SQLiteRepo do
  @moduledoc "A SQLite repository for the tests of the charts of a query (Fude.Query)."
  use Ecto.Repo, otp_app: :fude, adapter: Ecto.Adapters.SQLite3
end

defmodule FudeTest.PostgresRepo do
  @moduledoc "A PostgreSQL repository for the tests of Fude.Query, with FUDE_DB=postgres."
  use Ecto.Repo, otp_app: :fude, adapter: Ecto.Adapters.Postgres
end

defmodule FudeTest.MySQLRepo do
  @moduledoc "A MySQL repository for the tests of Fude.Query, with FUDE_DB=mysql."
  use Ecto.Repo, otp_app: :fude, adapter: Ecto.Adapters.MyXQL
end

defmodule FudeTest.Order do
  @moduledoc "An order, stored in SQLite."
  use Ecto.Schema

  schema "orders" do
    field :status, :string
    field :channel, :string
    field :total, :float
    field :items, :integer
    field :placed_on, :date
    field :placed_at, :utc_datetime
  end
end
