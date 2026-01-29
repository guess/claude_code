defmodule ClaudeCode.Adapter.Remote.Transport do
  @moduledoc """
  Behaviour for remote transport implementations.

  Transports abstract the network communication layer between the Elixir SDK
  and a remote container running the Claude CLI. Different transport
  implementations can use WebSockets, Server-Sent Events, FLAME, etc.

  ## Message Protocol

  Transports receive raw data from the remote endpoint and forward it to
  a subscriber process. The transport is responsible for:

  1. Establishing and maintaining connections
  2. Forwarding received data to the subscriber
  3. Handling disconnection and reconnection
  4. Sending input data to the remote endpoint

  ## Subscriber Messages

  Transports send the following messages to the subscriber:

  - `{:transport_data, data}` - Raw data received from the remote endpoint
  - `{:transport_connected, endpoint}` - Connection established
  - `{:transport_disconnected, reason}` - Connection lost
  - `{:transport_error, reason}` - Error occurred

  ## Implementations

  - `ClaudeCode.Adapter.Remote.Transport.WebSocket` - WebSocket-based transport
  """

  @type state :: term()
  @type endpoint :: String.t()
  @type opts :: keyword()
  @type reason :: term()

  @doc """
  Connects to the remote endpoint.

  ## Parameters

  - `endpoint` - The URL or address of the remote endpoint
  - `opts` - Connection options including:
    - `:subscriber` (required) - PID to receive transport messages
    - `:connect_timeout` - Connection timeout in milliseconds
    - Any transport-specific options

  ## Returns

  - `{:ok, pid}` - Connection established, returns transport process PID
  - `{:error, reason}` - Connection failed
  """
  @callback connect(endpoint(), opts()) :: {:ok, pid()} | {:error, reason()}

  @doc """
  Sends input data to the remote endpoint.

  The data is typically a JSON-encoded message that will be written to
  the CLI's stdin on the remote container.

  ## Parameters

  - `transport` - The transport process PID
  - `data` - Binary data to send

  ## Returns

  - `:ok` - Data sent successfully
  - `{:error, reason}` - Send failed
  """
  @callback send_input(transport :: pid(), data :: binary()) :: :ok | {:error, reason()}

  @doc """
  Gracefully disconnects from the remote endpoint.

  ## Parameters

  - `transport` - The transport process PID

  ## Returns

  - `:ok` - Disconnected successfully
  """
  @callback disconnect(transport :: pid()) :: :ok

  @doc """
  Checks if the transport connection is alive.

  ## Parameters

  - `transport` - The transport process PID

  ## Returns

  - `true` - Connection is active
  - `false` - Connection is not active
  """
  @callback alive?(transport :: pid()) :: boolean()
end
