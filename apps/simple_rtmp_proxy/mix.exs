defmodule SimpleRtmpProxy.Mixfile do
  use Mix.Project

  def project do
    [
      app: :simple_rtmp_proxy,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.4",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger],
     mod: {SimpleRtmpProxy, []}]
  end

  defp deps do
    [
      {:gen_rtmp_server, in_umbrella: true},
      {:gen_rtmp_client, in_umbrella: true},
    ]
  end
end
