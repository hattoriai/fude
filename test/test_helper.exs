{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: FudeTest.PubSub)
{:ok, _pid} = FudeTest.Endpoint.start_link()
# The :build tests run `mix fude.build` (npm and network on the first
# run) and `mix hex.build`: `mix test --include build`.
ExUnit.start(exclude: [:build])
