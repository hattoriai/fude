defmodule Mix.Tasks.Fude.Build do
  @shortdoc "Builds the chart bundles and the style sheets into priv/static"

  @moduledoc """
  Builds the Fude charts into `priv/static`.

      $ mix fude.build

  This task is for work on Fude itself. An application that uses Fude
  gets the built files in the Hex package and does not run this task: in
  any project but Fude, the task stops with an error before it changes
  a file.

  The task:

    1. Runs `npm ci` in `assets/` when `assets/node_modules` is missing or
       `assets/package-lock.json` changed since the last install.
    2. Empties `priv/static`, so that it holds only the files of this
       build.
    3. Runs esbuild (the `esbuild` Mix package) with the `:fude_esm` and
       `:fude_cjs` profiles.
    4. Copies `assets/css/fude.css` and `assets/css/fude-sumi.css` to
       `priv/static/`, and the maps of `assets/maps/` to
       `priv/static/maps/`.

  After the task, `priv/static` holds exactly these files, which are the
  files of the Hex package.

  It needs `npm` on the path and the `:esbuild` dependency, which is
  available in the `:dev` environment.
  """

  use Mix.Task

  @compile {:no_warn_undefined, Esbuild}

  @assets "assets"
  @static "priv/static"
  @lock_hash "node_modules/.fude-lock-sha256"
  @profiles [:fude_esm, :fude_cjs]
  @stylesheets ["fude.css", "fude-sumi.css"]

  @impl Mix.Task
  def run(_args) do
    ensure_fude!(Mix.Project.config())
    Mix.Task.run("loadpaths")

    unless Code.ensure_loaded?(Esbuild) do
      Mix.raise("""
      mix fude.build needs the :esbuild dependency, which is available in \
      the :dev environment. Run it as `MIX_ENV=dev mix fude.build`.\
      """)
    end

    {:ok, _apps} = Application.ensure_all_started(:esbuild)

    install_packages()
    File.rm_rf!(@static)
    File.mkdir_p!(@static)
    Enum.each(@profiles, &bundle/1)
    Enum.each(@stylesheets, &copy_stylesheet/1)
    File.cp_r!(Path.join(@assets, "maps"), Path.join(@static, "maps"))

    Mix.shell().info("Fude assets are in #{@static}/")
  end

  # The task empties priv/static, so it must never run in an application.
  @doc false
  @spec ensure_fude!(keyword()) :: :ok
  def ensure_fude!(config) do
    if config[:app] == :fude do
      :ok
    else
      Mix.raise(
        "mix fude.build is for work on Fude itself; an app gets the built files in the Hex package"
      )
    end
  end

  defp install_packages do
    lock = Path.join(@assets, "package-lock.json")
    stamp = Path.join(@assets, @lock_hash)
    hash = lock |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    if File.dir?(Path.join(@assets, "node_modules")) and File.read(stamp) == {:ok, hash} do
      Mix.shell().info("assets/node_modules is up to date")
    else
      npm = System.find_executable("npm") || Mix.raise("mix fude.build needs npm on the path")
      Mix.shell().info("Running npm ci in assets/")

      case System.cmd(npm, ["ci", "--prefix", @assets], into: IO.stream(), stderr_to_stdout: true) do
        {_output, 0} -> File.write!(stamp, hash)
        {_output, status} -> Mix.raise("npm ci exited with status #{status}")
      end
    end
  end

  defp bundle(profile) do
    case Esbuild.install_and_run(profile, []) do
      0 -> :ok
      status -> Mix.raise("esbuild #{profile} exited with status #{status}")
    end
  end

  defp copy_stylesheet(name) do
    File.cp!(Path.join([@assets, "css", name]), Path.join(@static, name))
  end
end
