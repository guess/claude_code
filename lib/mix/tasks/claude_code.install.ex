defmodule Mix.Tasks.ClaudeCode.Install do
  @shortdoc "Installs the Claude CLI binary"

  @moduledoc """
  Installs the Claude CLI binary.

  ## Usage

      mix claude_code.install

  ## Options

  - `--version VERSION` - Install a specific version (default: "latest")
  - `--if-missing` - Only install if the CLI is not already present
  - `--force` - Reinstall even if already present

  ## Examples

      # Install the latest version
      mix claude_code.install

      # Install a specific version
      mix claude_code.install --version 2.1.29

      # Only install if not present (useful in CI)
      mix claude_code.install --if-missing

      # Force reinstall
      mix claude_code.install --force

  ## Configuration

  You can configure the default version in your config:

      config :claude_code,
        cli_version: "2.1.29",     # Default version to install
        cli_dir: "/custom/path"    # Custom installation directory

  The CLI binary is installed to `priv/bin/` by default.
  """

  use Mix.Task

  @switches [
    version: :string,
    if_missing: :boolean,
    force: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _args} = OptionParser.parse!(args, strict: @switches)

    version = opts[:version] || ClaudeCode.Installer.configured_version()
    if_missing = opts[:if_missing] || false
    force = opts[:force] || false

    bundled_path = ClaudeCode.Installer.bundled_path()
    bundled_exists? = File.exists?(bundled_path)

    cond do
      if_missing && bundled_exists? ->
        Mix.shell().info("Claude CLI already bundled at #{bundled_path}")

      !force && bundled_exists? ->
        Mix.shell().info("""
        Claude CLI is already bundled at #{bundled_path}

        Use --force to reinstall or --version to install a different version.
        """)

      true ->
        install_cli(version)
    end
  end

  defp install_cli(version) do
    Mix.shell().info("Installing Claude CLI#{version_label(version)}...")
    Mix.shell().info("")

    try do
      case ClaudeCode.Installer.install!(version: version, return_info: true) do
        {:ok, info} ->
          size_mb = info.size_bytes / (1024 * 1024)

          Mix.shell().info("""
          ✓ Claude CLI installed successfully!

            Version: #{info.version || "unknown"}
            Path:    #{info.path}
            Size:    #{:erlang.float_to_binary(size_mb, decimals: 2)} MB
          """)

        :ok ->
          Mix.shell().info("""
          ✓ Claude CLI installed to #{ClaudeCode.Installer.bundled_path()}
          """)
      end
    rescue
      e ->
        Mix.shell().error("""
        ✗ Failed to install Claude CLI

        Error: #{Exception.message(e)}

        You can try installing manually:
          curl -fsSL https://claude.ai/install.sh | bash

        Or configure an explicit path:
          config :claude_code, cli_path: "/path/to/claude"
        """)

        exit({:shutdown, 1})
    end
  end

  defp version_label("latest"), do: ""
  defp version_label(version), do: " v#{version}"
end
