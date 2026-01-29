defmodule ClaudeCode.Adapter.Remote.Backend.Custom do
  @moduledoc """
  Custom backend for user-provided endpoints.

  This backend is for scenarios where the user manages their own container
  infrastructure. No container provisioning is performed - the user provides
  a WebSocket endpoint that's already running the transport server.

  ## Usage

  ```elixir
  {:ok, session} = ClaudeCode.start_link(
    adapter: {ClaudeCode.Adapter.Remote, [
      backend: ClaudeCode.Adapter.Remote.Backend.Custom,
      endpoint: "wss://my-container.example.com:8080"
    ]}
  )
  ```

  ## Container Setup

  The user's container must:

  1. Have Node.js 18+ installed
  2. Have Claude CLI installed (`npm install -g @anthropic-ai/claude-code`)
  3. Run the transport server (see `priv/container/transport-server/`)
  4. Have network access to `api.anthropic.com`
  5. Expose the WebSocket endpoint

  The SDK provides a reference transport server implementation in
  `priv/container/transport-server/` that can be deployed to any container.
  """

  @behaviour ClaudeCode.Adapter.Remote.Backend

  @impl true
  def provision(_spec, opts) do
    endpoint = Keyword.fetch!(opts, :endpoint)

    # No actual provisioning - user manages their own infrastructure
    {:ok,
     %{
       id: generate_container_id(),
       endpoint: endpoint,
       status: :running,
       metadata: %{
         backend: :custom,
         provisioned_at: DateTime.utc_now()
       }
     }}
  end

  @impl true
  def terminate(_container_id, _opts) do
    # No-op for custom backend - user manages their own infrastructure
    :ok
  end

  @impl true
  def get_info(container_id, opts) do
    endpoint = Keyword.get(opts, :endpoint)

    if endpoint do
      {:ok,
       %{
         id: container_id,
         endpoint: endpoint,
         status: :unknown,
         metadata: %{backend: :custom}
       }}
    else
      {:error, :not_found}
    end
  end

  @impl true
  def available?(_opts) do
    # Custom backend is always "available" - actual availability depends on
    # whether the user's endpoint is reachable
    true
  end

  @impl true
  def health_check(_container_id, _opts) do
    # For custom backend, health is determined by transport connection
    # Return :unknown and let the transport layer handle health checking
    :healthy
  end

  defp generate_container_id do
    "custom-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
