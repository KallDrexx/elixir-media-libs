defmodule RtmpHandshake.Mixfile do
  use Mix.Project

  def project do
    [app: :rtmp_handshake,
     version: "1.0.0",
     build_path: "../../_build",
     config_path: "../../config/config.exs",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description,
     package: package,
     deps: deps]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [{:ex_doc, "~> 0.14", only: :dev}]
  end

  defp package do
    [
      name: :eml_rtmp_handshake,
      maintainers: ["Matthew Shapiro"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/KallDrexx/elixir-media-libs/tree/master/apps/rtmp_handshake"}
    ]
  end

  defp description do
    "Library providing the capability to process and perform RTMP handshakes"
  end
end
