defmodule Mix.Tasks.ClaudeCode.Install do
  @shortdoc "Installs the Claude CLI binary"

  @moduledoc """
  Installs the Claude CLI binary.

  ## Usage

      mix claude_code.install

  ## Options

  - `--version VERSION` - Install a specific version (default: SDK's tested version)
  - `--force` - Reinstall even if already present and version matches

  ## Examples

      # Install or update to the configured version
      mix claude_code.install

      # Install a specific version
      mix claude_code.install --version x.y.z

      # Force reinstall even if version matches
      mix claude_code.install --force

  ## Configuration

  You can configure the default version in your config:

      config :claude_code,
        cli_version: "x.y.z",      # Default version to install
        cli_dir: "/custom/path"    # Custom installation directory

  The CLI binary is installed to `priv/bin/` by default.
  """

  use Mix.Task

  alias ClaudeCode.Adapter.Port.Installer

  @switches [
    version: :string,
    force: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _args} = OptionParser.parse!(args, strict: @switches)

    version = opts[:version] || Installer.configured_version()
    force = opts[:force] || false

    bundled_path = Installer.bundled_path()

    cond do
      force ->
        install_cli(version)

      !File.exists?(bundled_path) ->
        install_cli(version)

      true ->
        check_version_and_update(bundled_path, version)
    end
  end

  defp check_version_and_update(bundled_path, target_version) do
    case Installer.version_of(bundled_path) do
      {:ok, ^target_version} ->
        Mix.shell().info("Claude CLI v#{target_version} is already installed at #{bundled_path}")

      {:ok, current} ->
        Mix.shell().info("Claude CLI version mismatch: v#{current} installed, v#{target_version} expected")
        install_cli(target_version)

      {:error, reason} ->
        Mix.shell().info("Could not determine installed version (#{inspect(reason)}), reinstalling...")
        install_cli(target_version)
    end
  end

  defp install_cli(version) do
    Mix.shell().info("Installing Claude CLI#{version_label(version)}...")

    try do
      case Installer.install!(version: version, return_info: true) do
        {:ok, info} ->
          size_str = format_size(info.size_bytes)

          Mix.shell().info("""
          ✓ Claude CLI installed successfully!

            Version: #{info.version || "unknown"}
            Path:    #{info.path}
            Size:    #{size_str}
          """)

        :ok ->
          Mix.shell().info("""
          ✓ Claude CLI installed to #{Installer.bundled_path()}
          """)
      end
    rescue
      e in [RuntimeError, File.Error] ->
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

  defp format_size(nil), do: "unknown"
  defp format_size(0), do: "unknown"

  defp format_size(bytes) when is_integer(bytes) do
    size_mb = bytes / (1024 * 1024)
    "#{:erlang.float_to_binary(size_mb, decimals: 2)} MB"
  end
end
