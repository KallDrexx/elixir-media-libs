defmodule SimpleRtmpSystem.Mixfile do
  use Mix.Project

  def project do
    [app: :simple_rtmp_system,
     version: "0.1.0",
     build_path: "../../_build",
     config_path: "../../config/config.exs",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      mod: {SimpleRtmpSystem, []},
      env: [
        rtmp_port: 1935,
        rtmp_director_module: RtmpServer.AcceptAllDirector # TODO: change to RSR specific one
      ],
      applications: [:logger]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # To depend on another app inside the umbrella:
  #
  #   {:myapp, in_umbrella: true}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:rtmp_server, in_umbrella: true},
      {:dialyxir, "~> 0.3.5", only: [:dev]}
    ]
  end
end
