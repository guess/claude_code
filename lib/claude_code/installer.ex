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
        cli_version: "2.1.29",           # Version to install (default: SDK's tested version)
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

  # Common installation locations relative to home directory
  # Note: /usr/local/bin/claude is checked via System.find_executable in bin_path/0
  @unix_locations [
    ".npm-global/bin/claude",
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

  Defaults to the SDK's tested version (currently "2.1.29") if not configured.

  ## Examples

      iex> ClaudeCode.Installer.configured_version()
      "2.1.29"
  """
  # Default CLI version - update this when releasing new SDK versions
  @default_cli_version "2.1.29"

  @spec configured_version() :: String.t()
  def configured_version do
    Application.get_env(:claude_code, :cli_version, @default_cli_version)
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
      {:error, :not_found} -> raise cli_not_found_message()
    end
  end

  @doc """
  Installs the Claude CLI using the official Anthropic install script.

  The binary is installed to the configured `cli_dir` (default: priv/bin/).

  ## Options

  - `:version` - Version to install (default: configured version)
  - `:return_info` - When true, returns `{:ok, info_map}` instead of `:ok` (default: false).
    The info map contains: `version`, `path`, `size_bytes`, `source_path`.

  ## Examples

      iex> ClaudeCode.Installer.install!()
      :ok

      iex> ClaudeCode.Installer.install!(version: "2.1.29")
      :ok

      iex> ClaudeCode.Installer.install!(return_info: true)
      {:ok, %{version: "2.1.29", path: "/path/to/claude", size_bytes: 1234567, source_path: "/orig/path"}}
  """
  @spec install!(keyword()) :: :ok | {:ok, map()}
  def install!(opts \\ []) do
    version = Keyword.get(opts, :version, configured_version())
    return_info = Keyword.get(opts, :return_info, false)

    Logger.debug("Installing Claude CLI version: #{version}")

    # Create cli_dir if it doesn't exist
    File.mkdir_p!(cli_dir())

    # Run the official install script
    case run_install_script(version) do
      {:ok, installed_path, installed_version} ->
        # Copy the binary to our cli_dir
        dest_path = copy_binary_to_cli_dir(installed_path)
        size_bytes = get_file_size(dest_path)
        Logger.debug("Claude CLI installed successfully to #{dest_path}")

        if return_info do
          {:ok,
           %{
             version: installed_version,
             path: dest_path,
             size_bytes: size_bytes,
             source_path: installed_path
           }}
        else
          :ok
        end

      {:error, {:install_failed, exit_code, output}} ->
        Logger.error("""
        Claude CLI installation failed with exit code #{exit_code}.
        Install script output:
        #{output}
        """)

        raise "Failed to install Claude CLI: install script exited with code #{exit_code}"

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

    # Capture output to parse the installed version
    case System.cmd("bash", ["-c", script_cmd], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse the installed version from output and find that specific binary
        installed_version = parse_installed_version(output)

        case find_installed_binary(installed_version) do
          {:ok, path} -> {:ok, path, installed_version}
          error -> error
        end

      {output, exit_code} ->
        {:error, {:install_failed, exit_code, output}}
    end
  end

  defp run_windows_install_script(version) do
    # The PowerShell script accepts $Target as a positional parameter
    # We use scriptblock to pass the version argument properly
    script_cmd =
      if version == "latest" do
        "irm #{@windows_install_script_url} | iex"
      else
        "& ([scriptblock]::Create((irm #{@windows_install_script_url}))) '#{version}'"
      end

    Logger.debug("Running install script: #{script_cmd}")

    case System.cmd("powershell", ["-Command", script_cmd], stderr_to_stdout: true) do
      {output, 0} ->
        installed_version = parse_installed_version(output)

        case find_installed_binary(installed_version) do
          {:ok, path} -> {:ok, path, installed_version}
          error -> error
        end

      {output, exit_code} ->
        {:error, {:install_failed, exit_code, output}}
    end
  end

  defp find_installed_binary(installed_version) do
    home = System.user_home!()

    # The install script stores versioned binaries in ~/.local/share/claude/versions/
    # and creates a symlink at ~/.local/bin/claude
    # We want the specific version that was just installed, not whatever the symlink points to
    versioned_path =
      if installed_version do
        Path.join([home, ".local", "share", "claude", "versions", installed_version])
      end

    symlink_path = Path.join([home, ".local", "bin", @claude_binary])

    cond do
      # First, check for the specific versioned binary
      versioned_path && File.exists?(versioned_path) ->
        Logger.debug("Found versioned binary at #{versioned_path}")
        {:ok, versioned_path}

      # Fallback to symlink location
      File.exists?(symlink_path) ->
        Logger.debug("Using symlinked binary at #{symlink_path}")
        {:ok, symlink_path}

      # Last resort: general search
      path = find_system_cli() ->
        {:ok, path}

      true ->
        {:error, :binary_not_found_after_install}
    end
  end

  defp parse_installed_version(output) do
    # Parse "Version: 2.1.29" from install script output
    case Regex.run(~r/Version:\s*(\d+\.\d+\.\d+)/, output) do
      [_, version] ->
        version

      _ ->
        Logger.warning("Could not parse version from install script output: #{String.slice(output, 0, 200)}")

        nil
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

  defp get_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        size

      {:error, reason} ->
        Logger.warning("Could not determine file size for #{path}: #{inspect(reason)}")
        nil
    end
  end

  defp parse_version_output(output) do
    # Expected format: "1.0.24 (Claude Code)" or "2.1.29 (Claude Code)"
    # Extract the version number which is the first word
    output
    |> String.trim()
    |> String.split(~r/\s+/)
    |> List.first("")
    |> String.trim_leading("v")
  end

  @doc """
  Returns the error message shown when the CLI binary cannot be found.

  Used by both the Installer and CLI modules to provide consistent error messaging.
  """
  @spec cli_not_found_message() :: String.t()
  def cli_not_found_message do
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
