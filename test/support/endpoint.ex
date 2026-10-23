defmodule FudeTest.ErrorHTML do
  @moduledoc "Error pages for the test endpoint."

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule FudeTest.Router do
  @moduledoc "The router of the test endpoint."
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)
    live("/sales", FudeTest.SalesLive)
  end
end

defmodule FudeTest.Endpoint do
  @moduledoc "A Phoenix endpoint for the `Fude.Components` and `Fude.Test` tests. It runs no server."
  use Phoenix.Endpoint, otp_app: :fude

  plug(Plug.Session, store: :cookie, key: "_fude_test", signing_salt: "fude-test")
  plug(FudeTest.Router)
end
