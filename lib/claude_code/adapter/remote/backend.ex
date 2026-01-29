defmodule ClaudeCode.Adapter.Remote.Backend do
  @moduledoc """
  Behaviour for container backend implementations.

  Backends abstract container provisioning and lifecycle management.
  Different implementations can work with various container platforms
  (Modal, E2B, Fly.io, etc.) or custom infrastructure.

  ## Container Requirements

  Remote containers must have:

  1. Node.js 18+
  2. Claude CLI installed (`npm install -g @anthropic-ai/claude-code`)
  3. Transport server (WebSocket bridge to CLI stdin/stdout)
  4. Network access to `api.anthropic.com`

  ## Implementations

  - `ClaudeCode.Adapter.Remote.Backend.Custom` - User-provided endpoint (no provisioning)

  Future implementations may include Modal, E2B, Fly.io backends.
  """

  @type container_id :: String.t()
  @type opts :: keyword()
  @type reason :: term()

  @type container_spec :: %{
          optional(:image) => String.t(),
          optional(:env) => %{String.t() => String.t()},
          optional(:resources) => %{
            optional(:cpu) => float(),
            optional(:memory_mb) => non_neg_integer()
          }
        }

  @type container_info :: %{
          id: container_id(),
          endpoint: String.t(),
          status: :running | :stopped | :unknown,
          metadata: map()
        }

  @doc """
  Provisions a new container with the given specification.

  ## Parameters

  - `spec` - Container specification including image, env vars, resources
  - `opts` - Backend-specific options (credentials, region, etc.)

  ## Returns

  - `{:ok, container_info}` - Container provisioned successfully
  - `{:error, reason}` - Provisioning failed
  """
  @callback provision(spec :: container_spec(), opts()) ::
              {:ok, container_info()} | {:error, reason()}

  @doc """
  Terminates a running container.

  ## Parameters

  - `container_id` - The container identifier
  - `opts` - Backend-specific options

  ## Returns

  - `:ok` - Container terminated successfully
  - `{:error, reason}` - Termination failed
  """
  @callback terminate(container_id(), opts()) :: :ok | {:error, reason()}

  @doc """
  Gets information about a container.

  ## Parameters

  - `container_id` - The container identifier
  - `opts` - Backend-specific options

  ## Returns

  - `{:ok, container_info}` - Container info retrieved
  - `{:error, :not_found}` - Container not found
  - `{:error, reason}` - Other error
  """
  @callback get_info(container_id(), opts()) ::
              {:ok, container_info()} | {:error, :not_found | reason()}

  @doc """
  Checks if the backend is available and properly configured.

  ## Parameters

  - `opts` - Backend-specific options

  ## Returns

  - `true` - Backend is available
  - `false` - Backend is not available
  """
  @callback available?(opts()) :: boolean()

  @doc """
  Performs a health check on a container.

  ## Parameters

  - `container_id` - The container identifier
  - `opts` - Backend-specific options

  ## Returns

  - `:healthy` - Container is healthy and ready
  - `:unhealthy` - Container is running but not healthy
  - `{:error, reason}` - Health check failed
  """
  @callback health_check(container_id(), opts()) ::
              :healthy | :unhealthy | {:error, reason()}
end
