defmodule Mix.Tasks.Fude.ReleaseCheck do
  @shortdoc "Checks that priv/static holds the bundle files and the maps, and nothing else"

  @moduledoc """
  Checks the built files before a release of Fude.

      $ mix fude.release_check

  This task is for work on Fude itself; the `release` alias runs it
  after `mix fude.build` and before `mix hex.publish`. In any project
  but Fude, it stops with an error. It fails when:

    * one of the bundle files (`fude.esm.js`, `fude.cjs.js`, `fude.css`,
      `fude-sumi.css`, and the maps `maps/world.json` and
      `maps/us-states.json`) is missing from `priv/static`, or is empty
      (the empty files that CI makes are not a build);
    * `priv/static` holds any other file;
    * the `version` of `package.json` is not the version of `mix.exs`.
  """

  use Mix.Task

  @static "priv/static"
  @files ~w(fude.esm.js fude.cjs.js fude.css fude-sumi.css maps/world.json maps/us-states.json)

  @impl Mix.Task
  def run(_args) do
    config = Mix.Project.config()
    ensure_fude!(config)
    version = config[:version]

    case check(@static, "package.json", version) do
      :ok ->
        Mix.shell().info(
          "#{@static} holds the bundle files and the maps, and nothing else, and package.json has version #{version}"
        )

      {:error, problems} ->
        Mix.raise("""
        Fude is not ready for a release:

        #{Enum.map_join(problems, "\n", &("  * " <> &1))}

        Build with `mix fude.build` (it empties #{@static} first); keep the \
        version of package.json equal to the version of mix.exs.\
        """)
    end
  end

  @doc false
  @spec ensure_fude!(keyword()) :: :ok
  def ensure_fude!(config) do
    if config[:app] == :fude do
      :ok
    else
      Mix.raise(
        "mix fude.release_check is for work on Fude itself; it checks the files of a Fude release"
      )
    end
  end

  @doc false
  @spec check(Path.t(), Path.t(), String.t()) :: :ok | {:error, [String.t()]}
  def check(static, package_json, version) do
    # Every file under priv/static, by its path there.
    entries =
      static
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&Path.relative_to(&1, static))

    problems =
      Enum.flat_map(@files, &bundle_problems(static, &1, entries)) ++
        Enum.map(Enum.sort(entries -- @files), &"#{static}/#{&1} is not a bundle file") ++
        version_problems(package_json, version)

    if problems == [], do: :ok, else: {:error, problems}
  end

  defp bundle_problems(static, file, entries) do
    path = Path.join(static, file)

    cond do
      file not in entries -> ["#{path} is missing"]
      not File.regular?(path) -> ["#{path} is not a file"]
      File.stat!(path).size == 0 -> ["#{path} is empty"]
      true -> []
    end
  end

  defp version_problems(package_json, version) do
    with {:ok, source} <- File.read(package_json),
         {:ok, %{"version" => ^version}} <- JSON.decode(source) do
      []
    else
      _other -> ["the version of #{package_json} is not #{version}"]
    end
  end
end
