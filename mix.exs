defmodule ClaudeCode.MixProject do
  use Mix.Project

  @version "0.1.0-alpha.1"
  @source_url "https://github.com/guess/claude_code"

  def project do
    [
      app: :claude_code,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ],

      # Hex
      package: package(),
      description: "An idiomatic Elixir SDK for Claude Code AI assistant",

      # Docs
      name: "ClaudeCode",
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Production dependencies
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.0"},
      {:telemetry, "~> 1.2"},

      # Development and test dependencies
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:stream_data, "~> 1.1", only: [:test, :dev]}
    ]
  end

  defp aliases do
    [
      # Ensure code quality before commit
      quality: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ],
      # Run all tests with coverage
      "test.all": [
        "test --cover",
        "coveralls.html"
      ]
    ]
  end

  defp package do
    [
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "ROADMAP.md",
        "VISION.md",
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        "Core API": [
          ClaudeCode,
          ClaudeCode.Session,
          ClaudeCode.Options
        ],
        Messages: ~r/ClaudeCode.Message/,
        "Content Blocks": ~r/ClaudeCode.Content/,
        Permissions: ~r/ClaudeCode.Permission/,
        Errors: ~r/ClaudeCode.Error/,
        Testing: [
          ClaudeCode.Test
        ]
      ]
    ]
  end
end
