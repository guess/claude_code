defmodule ClaudeCode.MixProject do
  use Mix.Project

  alias ClaudeCode.Hook.Output

  @version "0.32.1"
  @source_url "https://github.com/guess/claude_code"

  def project do
    [
      app: :claude_code,
      version: @version,
      elixir: "~> 1.18",
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
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/project.plt"},
        plt_core_path: "priv/plts/core.plt",
        plt_add_apps: [:mix]
      ],

      # Hex
      package: package(),
      description: "Claude Agent SDK for Elixir – Build AI agents with Claude Code",

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
      extra_applications: [:logger, :inets, :ssl]
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
      {:nimble_ownership, "~> 1.0"},
      {:telemetry, "~> 1.2"},
      {:hermes_mcp, "~> 0.14"},

      # Development and test dependencies
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:stream_data, "~> 1.1", only: [:test, :dev]},
      # Tidewave
      {:bandit, "~> 1.0", only: [:dev, :test]},
      {:tidewave, "~> 0.5", only: :dev}
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
      ],
      # Run tidewave mcp in development
      tidewave: "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
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
      before_closing_body_tag: &before_closing_body_tag/1,
      nest_modules_by_prefix: [
        ClaudeCode.Message.SystemMessage,
        ClaudeCode.Message,
        ClaudeCode.Content,
        ClaudeCode.Session,
        ClaudeCode.Hook.PermissionDecision,
        Output
      ],
      extras: [
        "README.md",
        "CHANGELOG.md",
        # Introduction
        # Core Concepts
        "docs/guides/streaming-vs-single-mode.md",
        "docs/guides/streaming-output.md",
        "docs/guides/sessions.md",
        "docs/guides/stop-reasons.md",
        "docs/guides/structured-outputs.md",
        # Control & Permissions
        "docs/guides/permissions.md",
        "docs/guides/user-input.md",
        "docs/guides/hooks.md",
        "docs/guides/modifying-system-prompts.md",
        # Capabilities
        "docs/guides/mcp.md",
        "docs/guides/custom-tools.md",
        "docs/guides/skills.md",
        "docs/guides/slash-commands.md",
        "docs/guides/subagents.md",
        "docs/guides/plugins.md",
        # Production
        "docs/guides/hosting.md",
        "docs/guides/distributed-sessions.md",
        "docs/guides/secure-deployment.md",
        "docs/guides/file-checkpointing.md",
        "docs/guides/cost-tracking.md",
        # Testing
        "docs/reference/testing.md",
        # Reference
        "docs/integration/phoenix.md",
        "docs/reference/examples.md",
        "docs/reference/troubleshooting.md"
      ],
      groups_for_extras: [
        Introduction: [
          "README.md"
        ],
        "Core Concepts": [
          "docs/guides/streaming-vs-single-mode.md",
          "docs/guides/streaming-output.md",
          "docs/guides/sessions.md",
          "docs/guides/stop-reasons.md",
          "docs/guides/structured-outputs.md"
        ],
        "Control & Permissions": [
          "docs/guides/permissions.md",
          "docs/guides/user-input.md",
          "docs/guides/hooks.md",
          "docs/guides/modifying-system-prompts.md"
        ],
        Capabilities: [
          "docs/guides/mcp.md",
          "docs/guides/custom-tools.md",
          "docs/guides/skills.md",
          "docs/guides/slash-commands.md",
          "docs/guides/subagents.md",
          "docs/guides/plugins.md"
        ],
        Production: [
          "docs/guides/hosting.md",
          "docs/guides/distributed-sessions.md",
          "docs/guides/secure-deployment.md",
          "docs/guides/file-checkpointing.md",
          "docs/guides/cost-tracking.md"
        ],
        Testing: [
          "docs/reference/testing.md"
        ],
        Reference: [
          "docs/integration/phoenix.md",
          "docs/reference/examples.md",
          "docs/reference/troubleshooting.md"
        ]
      ],
      groups_for_modules: [
        "Core API": [
          ClaudeCode,
          ClaudeCode.Session,
          ClaudeCode.Supervisor
        ],
        Configuration: [
          ClaudeCode.Options,
          ClaudeCode.Agent
        ],
        Streaming: [
          ClaudeCode.Stream
        ],
        Messages: ~r/ClaudeCode\.Message(?!\.SystemMessage\.)/,
        "System Messages": ~r/ClaudeCode\.Message\.SystemMessage\./,
        "Content Blocks": [
          ClaudeCode.Content,
          ~r/ClaudeCode\.Content\./
        ],
        "Session Types": [
          ClaudeCode.Session.AccountInfo,
          ClaudeCode.Session.AgentInfo,
          ClaudeCode.Session.PermissionDenial,
          ClaudeCode.Session.PermissionMode,
          ClaudeCode.Session.SlashCommand
        ],
        Model: [
          ClaudeCode.Model,
          ClaudeCode.Model.Effort,
          ClaudeCode.Model.Info,
          ClaudeCode.Model.Usage,
          ClaudeCode.Usage
        ],
        Sandbox: [
          ClaudeCode.Sandbox,
          ClaudeCode.Sandbox.Filesystem,
          ClaudeCode.Sandbox.Network
        ],
        Hooks: [
          ClaudeCode.Hook,
          Output,
          ClaudeCode.Hook.Output.Async,
          ClaudeCode.Hook.Output.PreToolUse,
          ClaudeCode.Hook.Output.PostToolUse,
          ClaudeCode.Hook.Output.PostToolUseFailure,
          ClaudeCode.Hook.Output.UserPromptSubmit,
          ClaudeCode.Hook.Output.SessionStart,
          ClaudeCode.Hook.Output.Notification,
          ClaudeCode.Hook.Output.SubagentStart,
          ClaudeCode.Hook.Output.PreCompact,
          ClaudeCode.Hook.Output.PermissionRequest,
          ClaudeCode.Hook.PermissionDecision.Allow,
          ClaudeCode.Hook.PermissionDecision.Deny
        ],
        Plugins: [
          ClaudeCode.Plugin,
          ClaudeCode.Plugin.Marketplace
        ],
        "MCP Integration": ~r/ClaudeCode\.MCP/,
        Testing: [
          ClaudeCode.Test,
          ClaudeCode.Test.Factory
        ],
        Installation: [
          ClaudeCode.Adapter.Port.Installer,
          ClaudeCode.Adapter.Port.Resolver,
          Mix.Tasks.ClaudeCode.Install,
          Mix.Tasks.ClaudeCode.Uninstall,
          Mix.Tasks.ClaudeCode.Path
        ],
        Internal: [
          ClaudeCode.Adapter,
          ClaudeCode.Adapter.Port,
          ClaudeCode.Adapter.Node,
          ClaudeCode.Adapter.Test,
          ClaudeCode.CLI.Command,
          ClaudeCode.CLI.Control,
          ClaudeCode.CLI.Control.Types,
          ClaudeCode.CLI.Input,
          ClaudeCode.CLI.Parser,
          ClaudeCode.History,
          ClaudeCode.JSONEncoder
        ]
      ]
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(:epub), do: ""
end
