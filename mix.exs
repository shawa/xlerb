defmodule Xlerb.MixProject do
  use Mix.Project

  def project do
    [
      app: :xlerb,
      version: "0.0.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: compilers(),
      erlc_paths: ["src"],
      escript: escript()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    []
  end

  defp compilers do
    [:leex, :yecc | Mix.compilers()]
  end

  defp escript do
    [main_module: Xlerb.CLI]
  end
end
