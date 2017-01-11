defmodule GenRtmpServer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :gen_rtmp_server,
      version: "0.1.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.4",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      description: description(),
      package: package(),
      deps: deps()
     ]
  end

  def application do
    [applications: [:logger, :ranch]]
  end

  defp deps do
    get_umbrella_dependencies(Mix.env) ++
    [
      get_ranch_dependency(Mix.env),
      {:uuid, "~> 1.1"},
      {:ex_doc, "~> 0.14", only: :dev}
    ]
  end

  defp get_umbrella_dependencies(:umbrella) do
    [
      {:rtmp, in_umbrella: true},
    ]
  end

  defp get_umbrella_dependencies(_) do
    [
      {:rtmp, "~> 0.1.0", hex: :eml_rtmp},
    ]
  end

  defp get_ranch_dependency(:publish), do: {:ranch, "~> 1.2.1"}
  defp get_ranch_dependency(_), do: {:ranch, "~> 1.2.1", manager: :rebar}

  defp package do
    [
      name: :eml_gen_rtmp_server,
      maintainers: ["Matthew Shapiro"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/KallDrexx/elixir-media-libs/tree/master/apps/gen_rtmp_server"}
    ]
  end

  defp description do
    "Behaviour to make it easy to create custom RTMP servers"
  end
end
