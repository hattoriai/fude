{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: FudeTest.PubSub)
{:ok, _pid} = FudeTest.Endpoint.start_link()

# The Issho instance of the shared charts (Fude.Issho): everyone may do
# everything, and agents read the data of FudeTest.Reports.
Application.put_env(:fude, Fude.Issho, data: {FudeTest.Reports, :data})

{:ok, _pid} =
  Issho.start_link(
    name: FudeTest.Issho,
    pubsub: FudeTest.PubSub,
    policy: FudeTest.Policy,
    secret_key_base: String.duplicate("fude-test-secret-key-base-", 3),
    ttl: 50,
    awareness_interval: 5
  )

# The :build tests run `mix fude.build` (npm and network on the first
# run) and `mix hex.build`: `mix test --include build`.
ExUnit.start(exclude: [:build])
