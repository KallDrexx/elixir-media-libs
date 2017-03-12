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
      deps: deps(),
      escript: [
        main_module: SimpleRtmpProxy,
        name: "simple_rtmp_proxy.escript"
      ],
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:gen_rtmp_server, in_umbrella: true},
      {:gen_rtmp_client, in_umbrella: true},
    ]
  end
end
