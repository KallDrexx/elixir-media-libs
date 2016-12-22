defmodule RtmpSession.Mixfile do
  use Mix.Project

  def project do
    [app: :rtmp_session,
     version: "0.1.0",
     build_path: "../../_build",
     config_path: "../../config/config.exs",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description,
     package: package,
     deps: deps
    ]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [
      {:amf0, in_umbrella: true},
      {:dialyxir, "~> 0.3.5", only: [:dev]}
    ]
  end

  defp package do
    [
      name: :eml_rtmp_session,
      maintainers: ["Matthew Shapiro"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/KallDrexx/elixir-media-libs/tree/master/apps/rtmp_session"}
    ]
  end

  defp description do
    "Provides an abstraction of the RTMP protocol and represents a single peer in an RTMP connection"
  end
end
