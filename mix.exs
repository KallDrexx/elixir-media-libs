defmodule ElixirMediaLibs.Mixfile do
  use Mix.Project

  def project do
    [apps_path: "apps",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     dialyzer: [plt_add_deps: :transitive]
    ]
  end

  defp deps do
    [{:dialyxir, "~> 0.4.3", only: [:dev, :umbrella]}]
  end
end
