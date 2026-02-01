defmodule ClaudeCode.Installer do
  @moduledoc """
  Manages Claude CLI binary installation.

  This module handles automatic CLI binary management following patterns from
  `phoenixframework/esbuild` and `phoenixframework/tailwind`, using the official
  Anthropic install scripts.

  ## Installation Methods

  1. **Automatic** - CLI is installed on first use via `ensure_installed!/0`
  2. **Manual** - Run `mix claude_code.install` before using the SDK
  3. **Pre-installed** - Use system CLI from PATH or configure `:cli_path`

  ## Configuration

      # config/config.exs
      config :claude_code,
        cli_version: "latest",           # Version to install
        cli_path: nil,                    # Explicit path to binary
        cli_dir: nil                      # Directory for downloaded binary

  ## Resolution Order

  When finding the CLI binary, the following locations are checked in order:

  1. `:cli_path` option (explicit override)
  2. Application config `:cli_path`
  3. Bundled binary in `cli_dir` (default: priv/bin/)
  4. System PATH via `System.find_executable/1`
  5. Common installation locations (npm, yarn, home directory)

  ## Release Configuration

  For releases, you have several options:

  1. **Pre-install during build** - Run `mix claude_code.install` in your release build
  2. **Configure writable directory** - Set `:cli_dir` to a writable runtime location
  3. **Use system CLI** - Install via official scripts and rely on PATH
  """

  require Logger

  @claude_binary "claude"
  @install_script_url "https://claude.ai/install.sh"
  @windows_install_script_url "https://claude.ai/install.ps1"

  # Common installation locations (based on Python SDK patterns)
  @unix_locations [
    ".npm-global/bin/claude",
    "/usr/local/bin/claude",
    ".local/bin/claude",
    "node_modules/.bin/claude",
    ".yarn/bin/claude",
    ".claude/local/claude"
  ]

  @windows_locations [
    ".local/bin/claude.exe",
    "AppData/Local/Claude/claude.exe"
  ]

  @doc """
  Returns the configured CLI version to install.

  Defaults to "latest" if not configured.

  ## Examples

      iex> ClaudeCode.Installer.configured_version()
      "latest"
  """
  @spec configured_version() :: String.t()
  def configured_version do
    Application.get_env(:claude_code, :cli_version, "latest")
  end

  @doc """
  Returns the directory where the CLI binary should be stored.

  Defaults to `priv/bin/` within the application directory.

  ## Examples

      iex> ClaudeCode.Installer.cli_dir()
      "/path/to/app/priv/bin"
  """
  @spec cli_dir() :: String.t()
  def cli_dir do
    case Application.get_env(:claude_code, :cli_dir) do
      nil -> default_cli_dir()
      dir -> dir
    end
  end

  @doc """
  Returns the path to the bundled CLI binary.

  This is the path where the installer places the CLI binary,
  not necessarily where it currently exists.

  ## Examples

      iex> ClaudeCode.Installer.bundled_path()
      "/path/to/app/priv/bin/claude"
  """
  @spec bundled_path() :: String.t()
  def bundled_path do
    binary_name = if windows?(), do: "claude.exe", else: @claude_binary
    Path.join(cli_dir(), binary_name)
  end

  @doc """
  Returns the path to the CLI binary, checking multiple locations.

  Resolution order:
  1. Application config `:cli_path` (explicit override)
  2. Bundled binary in `cli_dir`
  3. System PATH
  4. Common installation locations

  Returns `nil` if no binary is found.

  ## Examples

      iex> ClaudeCode.Installer.bin_path()
      {:ok, "/usr/local/bin/claude"}

      iex> ClaudeCode.Installer.bin_path()
      {:error, :not_found}
  """
  @spec bin_path() :: {:ok, String.t()} | {:error, :not_found}
  def bin_path do
    cond do
      # 1. Explicit config path
      path = Application.get_env(:claude_code, :cli_path) ->
        if File.exists?(path), do: {:ok, path}, else: {:error, :not_found}

      # 2. Bundled binary
      File.exists?(bundled_path()) ->
        {:ok, bundled_path()}

      # 3. System PATH
      path = System.find_executable(@claude_binary) ->
        {:ok, path}

      # 4. Common locations
      path = find_in_common_locations() ->
        {:ok, path}

      # Not found
      true ->
        {:error, :not_found}
    end
  end

  @doc """
  Finds the CLI binary or raises an error with installation instructions.

  ## Examples

      iex> ClaudeCode.Installer.bin_path!()
      "/usr/local/bin/claude"

      iex> ClaudeCode.Installer.bin_path!()
      ** (RuntimeError) Claude CLI not found...
  """
  @spec bin_path!() :: String.t()
  def bin_path! do
    case bin_path() do
      {:ok, path} -> path
      {:error, :not_found} -> raise cli_not_found_error()
    end
  end

  @doc """
  Installs the Claude CLI using the official Anthropic install script.

  The binary is installed to the configured `cli_dir` (default: priv/bin/).

  ## Options

  - `:version` - Version to install (default: configured version or "latest")

  ## Examples

      iex> ClaudeCode.Installer.install!()
      :ok

      iex> ClaudeCode.Installer.install!(version: "2.1.29")
      :ok
  """
  @spec install!(keyword()) :: :ok
  def install!(opts \\ []) do
    version = Keyword.get(opts, :version, configured_version())

    Logger.info("Installing Claude CLI version: #{version}")

    # Create cli_dir if it doesn't exist
    File.mkdir_p!(cli_dir())

    # Run the official install script
    case run_install_script(version) do
      {:ok, installed_path} ->
        # Copy the binary to our cli_dir
        copy_binary_to_cli_dir(installed_path)
        Logger.info("Claude CLI installed successfully to #{bundled_path()}")
        :ok

      {:error, reason} ->
        raise "Failed to install Claude CLI: #{inspect(reason)}"
    end
  end

  @doc """
  Ensures the CLI is installed, installing it if necessary.

  This is the lazy installation pattern - called automatically when
  the CLI is needed but not found.

  ## Examples

      iex> ClaudeCode.Installer.ensure_installed!()
      :ok
  """
  @spec ensure_installed!() :: :ok
  def ensure_installed! do
    case bin_path() do
      {:ok, _path} -> :ok
      {:error, :not_found} -> install!()
    end
  end

  @doc """
  Returns the version of the installed CLI binary.

  ## Examples

      iex> ClaudeCode.Installer.installed_version()
      {:ok, "2.1.29"}

      iex> ClaudeCode.Installer.installed_version()
      {:error, :not_found}
  """
  @spec installed_version() :: {:ok, String.t()} | {:error, term()}
  def installed_version do
    case bin_path() do
      {:ok, path} ->
        case System.cmd(path, ["--version"], stderr_to_stdout: true) do
          {output, 0} ->
            version = parse_version_output(output)
            {:ok, version}

          {error, _code} ->
            {:error, {:cli_error, error}}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Searches for the CLI in common installation locations.

  Returns the path if found, `nil` otherwise.
  """
  @spec find_in_common_locations() :: String.t() | nil
  def find_in_common_locations do
    locations = if windows?(), do: @windows_locations, else: @unix_locations

    home = System.user_home!()

    Enum.find_value(locations, fn relative_path ->
      path = Path.join(home, relative_path)
      if File.exists?(path), do: path
    end)
  end

  @doc """
  Searches for the CLI installed by the official script.

  The official script typically installs to:
  - Unix: ~/.local/bin/claude or ~/.claude/local/claude
  - Windows: %USERPROFILE%\\.local\\bin\\claude.exe

  Returns the path if found, `nil` otherwise.
  """
  @spec find_system_cli() :: String.t() | nil
  def find_system_cli do
    # First check PATH
    case System.find_executable(@claude_binary) do
      nil -> find_in_common_locations()
      path -> path
    end
  end

  # Private functions

  defp default_cli_dir do
    # Use priv/bin within the application directory
    case :code.priv_dir(:claude_code) do
      {:error, _} ->
        # Fallback for development
        Path.join([File.cwd!(), "priv", "bin"])

      priv_dir ->
        Path.join(to_string(priv_dir), "bin")
    end
  end

  defp windows? do
    case :os.type() do
      {:win32, _} -> true
      _ -> false
    end
  end

  defp run_install_script(version) do
    case :os.type() do
      {:unix, _} -> run_unix_install_script(version)
      {:win32, _} -> run_windows_install_script(version)
    end
  end

  defp run_unix_install_script(version) do
    # Build the install command
    # The install script accepts: stable|latest|VERSION as first positional arg
    # Example: curl -fsSL https://claude.ai/install.sh | bash -s -- 2.1.29
    script_cmd =
      if version == "latest" do
        "curl -fsSL #{@install_script_url} | bash"
      else
        "curl -fsSL #{@install_script_url} | bash -s -- #{version}"
      end

    Logger.debug("Running install script: #{script_cmd}")

    case System.cmd("bash", ["-c", script_cmd], stderr_to_stdout: true, into: IO.stream()) do
      {_output, 0} ->
        # Find where the script installed the binary
        find_installed_binary()

      {output, exit_code} ->
        {:error, {:install_failed, exit_code, output}}
    end
  end

  defp run_windows_install_script(version) do
    script_cmd =
      if version == "latest" do
        "irm #{@windows_install_script_url} | iex"
      else
        # Windows script version handling may differ
        "irm #{@windows_install_script_url} | iex"
      end

    Logger.debug("Running install script: #{script_cmd}")

    case System.cmd("powershell", ["-Command", script_cmd], stderr_to_stdout: true) do
      {_output, 0} ->
        find_installed_binary()

      {output, exit_code} ->
        {:error, {:install_failed, exit_code, output}}
    end
  end

  defp find_installed_binary do
    # The official script installs to common locations
    # Check them in order of likelihood
    case find_system_cli() do
      nil -> {:error, :binary_not_found_after_install}
      path -> {:ok, path}
    end
  end

  defp copy_binary_to_cli_dir(source_path) do
    dest_path = bundled_path()

    # Ensure directory exists
    File.mkdir_p!(cli_dir())

    # Copy the binary
    File.cp!(source_path, dest_path)

    # Make it executable on Unix
    if !windows?() do
      File.chmod!(dest_path, 0o755)
    end

    dest_path
  end

  defp parse_version_output(output) do
    # Expected format: "Claude Code v2.1.29" or similar
    output
    |> String.trim()
    |> String.split(~r/\s+/)
    |> List.last()
    |> String.trim_leading("v")
  end

  defp cli_not_found_error do
    """
    Claude CLI not found.

    Install it using one of these methods:

    1. Run the mix task:
       mix claude_code.install

    2. Install manually:
       curl -fsSL https://claude.ai/install.sh | bash

    3. Configure an explicit path:
       config :claude_code, cli_path: "/path/to/claude"

    For more information, visit: https://docs.anthropic.com/en/docs/claude-code
    """
  end
end
