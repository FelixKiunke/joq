defmodule Joq.Mixfile do
  use Mix.Project

  def project do
    [app: :joq,
     version: "0.2.0",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description,
     package: package,
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger, :uuid],
     mod: {Joq, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
      {:uuid, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:retry, "~> 0.5.0", only: :test}
    ]
  end

  defp description do
    """
    Non-persistent job queueing and processing library for Elixir.

    Has retries, delayed jobs, concurrency limiting, error handling etc.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md"],
      maintainers: ["Felix Kiunke"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/FelixKiunke/joq"}
    ]
  end
end
