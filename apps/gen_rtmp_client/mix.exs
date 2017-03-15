defmodule GenRtmpClient.Mixfile do
  use Mix.Project

  def project do
    [
      app: :gen_rtmp_client,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.4",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      package: package(),
      description: "Behaviour to make it easy to create custom RTMP clients",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.14", only: [:dev, :publish, :umbrella]} |
      get_umbrella_dependencies(Mix.env)
    ]
  end

  defp get_umbrella_dependencies(:umbrella) do
    [
      {:rtmp, in_umbrella: true},
    ]
  end

  defp get_umbrella_dependencies(_) do
    [
      {:rtmp, "~> 0.2.0", hex: :eml_rtmp},
    ]
  end

  defp package do
    [
      name: :eml_gen_rtmp_client,
      maintainers: ["Matthew Shapiro"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/KallDrexx/elixir-media-libs/tree/master/apps/gen_rtmp_client"}
    ]
  end
end
