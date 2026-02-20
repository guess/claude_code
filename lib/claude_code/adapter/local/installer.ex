defmodule ClaudeCode.Adapter.Local.Installer do
  @moduledoc """
  Manages Claude CLI binary installation.

  This module handles automatic CLI binary management following patterns from
  `phoenixframework/esbuild` and `phoenixframework/tailwind`, using the official
  Anthropic install scripts.

  ## Installation Methods

  1. **Automatic** - CLI is auto-installed to priv/bin/ on first use when `cli_path: :bundled` (the default)
  2. **Manual** - Run `mix claude_code.install` to pre-install the CLI
  3. **Pre-installed** - Use a system CLI with `cli_path: :global` or `cli_path: "/path/to/claude"`

  ## Configuration

      # config/config.exs
      config :claude_code,
        cli_path: :bundled,               # :bundled (default), :global, or "/path/to/claude"
        cli_version: "x.y.z",            # Version to install (default: SDK's tested version)
        cli_dir: nil                      # Directory for downloaded binary

  ## CLI Resolution Modes

  The `:cli_path` option controls how the CLI binary is found (see `ClaudeCode.Adapter.Local.Resolver.find_binary/1`):

  - `:bundled` (default) — Uses priv/bin/ binary. Auto-installs if missing.
    Verifies version matches the SDK's pinned version and re-installs on mismatch.
  - `:global` — Finds existing system install via PATH or common locations. No auto-install.
  - `"/path/to/claude"` — Uses that exact binary path.

  ## Release Configuration

  For releases, you have several options:

  1. **Pre-install during build** - Run `mix claude_code.install` in your release build
  2. **Configure writable directory** - Set `:cli_dir` to a writable runtime location
  3. **Use system CLI** - Set `cli_path: :global` and ensure `claude` is in PATH
  """

  alias ClaudeCode.SystemCmd

  require Logger

  @claude_binary "claude"
  @install_script_url "https://claude.ai/install.sh"
  @windows_install_script_url "https://claude.ai/install.ps1"

  # Common installation locations relative to home directory
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

  # Default CLI version - update this when releasing new SDK versions
  @default_cli_version "2.1.49"

  @doc """
  Returns the configured CLI version to install.

  Defaults to the SDK's tested version if not configured.

  ## Examples

      iex> ClaudeCode.Adapter.Local.Installer.configured_version()
      "#{@default_cli_version}"
  """
  @spec configured_version() :: String.t()
  def configured_version do
    Application.get_env(:claude_code, :cli_version, @default_cli_version)
  end

  @doc """
  Returns the directory where the CLI binary should be stored.

  Defaults to `priv/bin/` within the application directory.

  ## Examples

      iex> ClaudeCode.Adapter.Local.Installer.cli_dir()
      "/path/to/app/priv/bin"
  """
  @spec cli_dir() :: String.t()
  def cli_dir do
    Application.get_env(:claude_code, :cli_dir) || default_cli_dir()
  end

  @doc """
  Returns the path to the bundled CLI binary.

  This is the path where the installer places the CLI binary,
  not necessarily where it currently exists.

  ## Examples

      iex> ClaudeCode.Adapter.Local.Installer.bundled_path()
      "/path/to/app/priv/bin/claude"
  """
  @spec bundled_path() :: String.t()
  def bundled_path do
    binary_name = if windows?(), do: "claude.exe", else: @claude_binary
    Path.join(cli_dir(), binary_name)
  end

  @doc """
  Installs the Claude CLI using the official Anthropic install script.

  The binary is installed to the configured `cli_dir` (default: priv/bin/).

  ## Options

  - `:version` - Version to install (default: configured version)
  - `:return_info` - When true, returns `{:ok, info_map}` instead of `:ok` (default: false).
    The info map contains: `version`, `path`, `size_bytes`.

  ## Examples

      iex> ClaudeCode.Adapter.Local.Installer.install!()
      :ok

      iex> ClaudeCode.Adapter.Local.Installer.install!(version: "#{@default_cli_version}")
      :ok

      iex> ClaudeCode.Adapter.Local.Installer.install!(return_info: true)
      {:ok, %{version: "#{@default_cli_version}", path: "/path/to/claude", size_bytes: 1234567}}
  """
  @spec install!(keyword()) :: :ok | {:ok, map()}
  def install!(opts \\ []) do
    version = Keyword.get(opts, :version, configured_version())
    return_info = Keyword.get(opts, :return_info, false)

    Logger.debug("Installing Claude CLI version: #{version}")
    File.mkdir_p!(cli_dir())

    case run_install_script(version) do
      {:ok, dest_path, installed_version} ->
        Logger.debug("Claude CLI installed successfully to #{dest_path}")

        if return_info do
          {:ok, %{version: installed_version, path: dest_path, size_bytes: get_file_size(dest_path)}}
        else
          :ok
        end

      {:error, {:install_failed, exit_code, output}} ->
        Logger.error("Claude CLI installation failed (exit #{exit_code}): #{output}")
        raise "Failed to install Claude CLI: install script exited with code #{exit_code}"

      {:error, reason} ->
        raise "Failed to install Claude CLI: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the version of the CLI binary at the given path.

  Runs `claude --version` and parses the output.

  ## Examples

      iex> ClaudeCode.Adapter.Local.Installer.version_of("/usr/local/bin/claude")
      {:ok, "#{@default_cli_version}"}

      iex> ClaudeCode.Adapter.Local.Installer.version_of("/nonexistent")
      {:error, {:execution_failed, "enoent"}}
  """
  @spec version_of(String.t()) :: {:ok, String.t()} | {:error, term()}
  def version_of(path) do
    case SystemCmd.cmd(path, ["--version"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, parse_version_output(output)}
      {error, _code} -> {:error, {:cli_error, error}}
    end
  rescue
    e -> {:error, {:execution_failed, Exception.message(e)}}
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

  defp windows?, do: match?({:win32, _}, :os.type())

  defp run_install_script(version) do
    case :os.type() do
      {:unix, _} -> run_unix_install_script(version)
      {:win32, _} -> run_windows_install_script(version)
    end
  end

  defp run_unix_install_script(version) do
    script_cmd =
      if version == "latest" do
        "curl -fsSL #{@install_script_url} | bash"
      else
        "curl -fsSL #{@install_script_url} | bash -s -- #{version}"
      end

    run_install_in_temp_dir(
      shell: {"bash", ["-c", script_cmd]},
      env: fn tmp_dir -> [{"HOME", tmp_dir}] end,
      post_copy: fn dest -> File.chmod!(dest, 0o755) end
    )
  end

  defp run_windows_install_script(version) do
    script_cmd =
      if version == "latest" do
        "irm #{@windows_install_script_url} | iex"
      else
        "& ([scriptblock]::Create((irm #{@windows_install_script_url}))) '#{version}'"
      end

    run_install_in_temp_dir(
      shell: {"powershell", ["-Command", script_cmd]},
      env: fn tmp_dir -> [{"USERPROFILE", tmp_dir}, {"HOME", tmp_dir}] end
    )
  end

  # Shared installation flow: create temp dir, run script, copy binary, clean up.
  defp run_install_in_temp_dir(opts) do
    {shell, args} = Keyword.fetch!(opts, :shell)
    env_fn = Keyword.fetch!(opts, :env)
    post_copy = Keyword.get(opts, :post_copy)

    tmp_dir = create_temp_dir()
    env = env_fn.(tmp_dir)

    # Logger.debug("Running install script in #{tmp_dir}: #{shell} #{inspect(args)}")

    result =
      with {_output, 0} <- SystemCmd.cmd(shell, args, stderr_to_stdout: true, env: env),
           {:ok, path} <- find_installed_binary_in(tmp_dir) do
        dest = bundled_path()
        File.mkdir_p!(cli_dir())
        File.cp!(path, dest)
        if post_copy, do: post_copy.(dest)
        {:ok, dest, version_from_binary(dest)}
      else
        {output, exit_code} when is_integer(exit_code) ->
          {:error, {:install_failed, exit_code, output}}

        {:error, _} = error ->
          error
      end

    File.rm_rf(tmp_dir)
    result
  end

  defp find_installed_binary_in(home_dir) do
    binary_name = if windows?(), do: "claude.exe", else: @claude_binary

    # The install script places the binary at <home>/.local/bin/claude (symlink)
    # or <home>/.claude/local/claude
    candidate_paths = [
      Path.join([home_dir, ".local", "bin", binary_name]),
      Path.join([home_dir, ".claude", "local", binary_name])
    ]

    case Enum.find(candidate_paths, &File.exists?/1) do
      nil -> {:error, :binary_not_found_after_install}
      path -> {:ok, path}
    end
  end

  defp create_temp_dir do
    tmp_base = System.tmp_dir!()
    tmp_dir = Path.join(tmp_base, "claude_code_install_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)
    tmp_dir
  end

  defp version_from_binary(path) do
    case version_of(path) do
      {:ok, version} -> version
      {:error, _} -> nil
    end
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
    # Expected format: "x.y.z (Claude Code)"
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

    1. Run the mix task (installs to priv/bin/):
       mix claude_code.install

    2. Install manually and use global mode:
       curl -fsSL https://claude.ai/install.sh | bash
       # then: config :claude_code, cli_path: :global

    3. Configure an explicit path:
       config :claude_code, cli_path: "/path/to/claude"

    For more information, visit: https://docs.anthropic.com/en/docs/claude-code
    """
  end
end
