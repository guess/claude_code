# Phoenix Integration

This guide covers integrating ClaudeCode with Phoenix applications, including LiveView real-time streaming and controller patterns.

## Setup

Add ClaudeCode to your supervision tree:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyAppWeb.Endpoint,
    {ClaudeCode.Supervisor, [
      [name: :assistant]
    ]}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## LiveView with Async Queries (Recommended)

Use `query_async/3` for the cleanest LiveView integration. Messages are sent directly to your LiveView process:

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, messages: [], response: "", streaming: false, request_ref: nil)}
  end

  def handle_event("send", %{"message" => message}, socket) do
    {:ok, ref} = ClaudeCode.query_async(:assistant, message, include_partial_messages: true)

    messages = socket.assigns.messages ++ [%{role: :user, content: message}]
    {:noreply, assign(socket, messages: messages, response: "", streaming: true, request_ref: ref)}
  end

  # Stream started
  def handle_info({:claude_stream_started, ref}, %{assigns: %{request_ref: ref}} = socket) do
    {:noreply, socket}
  end

  # Receive streaming messages
  def handle_info({:claude_message, ref, message}, %{assigns: %{request_ref: ref}} = socket) do
    socket = process_message(socket, message)
    {:noreply, socket}
  end

  # Stream complete
  def handle_info({:claude_stream_end, ref}, %{assigns: %{request_ref: ref}} = socket) do
    messages = socket.assigns.messages ++ [%{role: :assistant, content: socket.assigns.response}]
    {:noreply, assign(socket, messages: messages, response: "", streaming: false, request_ref: nil)}
  end

  # Handle errors
  def handle_info({:claude_stream_error, ref, error}, %{assigns: %{request_ref: ref}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Error: #{inspect(error)}")
     |> assign(streaming: false, request_ref: nil)}
  end

  # Extract text from assistant messages
  defp process_message(socket, %ClaudeCode.Message.Assistant{message: %{content: content}}) do
    text = Enum.map_join(content, "", fn
      %ClaudeCode.Content.Text{text: t} -> t
      _ -> ""
    end)
    assign(socket, response: socket.assigns.response <> text)
  end
  defp process_message(socket, _other), do: socket

  def render(assigns) do
    ~H"""
    <div class="chat">
      <div class="messages">
        <%= for msg <- @messages do %>
          <div class={"message #{msg.role}"}><%= msg.content %></div>
        <% end %>
        <%= if @streaming do %>
          <div class="message assistant streaming"><%= @response %></div>
        <% end %>
      </div>

      <form phx-submit="send">
        <input type="text" name="message" disabled={@streaming} autocomplete="off" />
        <button type="submit" disabled={@streaming}>Send</button>
      </form>
    </div>
    """
  end
end
```

### Async Message Types

`query_async/3` sends these messages to your process:

| Message | Description |
|---------|-------------|
| `{:claude_stream_started, ref}` | Stream has begun |
| `{:claude_message, ref, message}` | A message from Claude (Assistant, Result, etc.) |
| `{:claude_stream_end, ref}` | Stream completed successfully |
| `{:claude_stream_error, ref, error}` | An error occurred |

### Interrupting Requests

Cancel an in-progress request (e.g., user clicks "Stop"):

```elixir
def handle_event("stop", _params, socket) do
  if socket.assigns.request_ref do
    ClaudeCode.interrupt(:assistant, socket.assigns.request_ref)
  end
  {:noreply, assign(socket, streaming: false, request_ref: nil)}
end
```

## LiveView with Task-Based Streaming

Alternative approach using Task with `query_stream/3`:

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, messages: [], response: "", streaming: false)}
  end

  def handle_event("send", %{"message" => message}, socket) do
    parent = self()

    Task.start(fn ->
      :assistant
      |> ClaudeCode.query_stream(message, include_partial_messages: true)
      |> ClaudeCode.Stream.text_deltas()
      |> Enum.each(fn chunk ->
        send(parent, {:chunk, chunk})
      end)

      send(parent, :complete)
    end)

    messages = socket.assigns.messages ++ [%{role: :user, content: message}]
    {:noreply, assign(socket, messages: messages, response: "", streaming: true)}
  end

  def handle_info({:chunk, chunk}, socket) do
    {:noreply, assign(socket, response: socket.assigns.response <> chunk)}
  end

  def handle_info(:complete, socket) do
    messages = socket.assigns.messages ++ [%{role: :assistant, content: socket.assigns.response}]
    {:noreply, assign(socket, messages: messages, response: "", streaming: false)}
  end

  def render(assigns) do
    ~H"""
    <div class="chat">
      <div class="messages">
        <%= for msg <- @messages do %>
          <div class={"message #{msg.role}"}><%= msg.content %></div>
        <% end %>
        <%= if @streaming do %>
          <div class="message assistant streaming"><%= @response %></div>
        <% end %>
      </div>

      <form phx-submit="send">
        <input type="text" name="message" disabled={@streaming} autocomplete="off" />
        <button type="submit" disabled={@streaming}>Send</button>
      </form>
    </div>
    """
  end
end
```

## Controller Integration

For traditional request/response patterns:

```elixir
defmodule MyAppWeb.ClaudeController do
  use MyAppWeb, :controller

  def ask(conn, %{"prompt" => prompt}) do
    case ClaudeCode.query(:assistant, prompt) do
      {:ok, response} ->
        json(conn, %{response: response})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: inspect(reason)})
    end
  end
end
```

## Streaming HTTP Response

For Server-Sent Events or chunked responses:

```elixir
def stream(conn, %{"prompt" => prompt}) do
  conn = put_resp_header(conn, "content-type", "text/event-stream")
  conn = send_chunked(conn, 200)

  :assistant
  |> ClaudeCode.query_stream(prompt)
  |> ClaudeCode.Stream.text_content()
  |> Enum.reduce_while(conn, fn chunk, conn ->
    case chunk(conn, "data: #{chunk}\n\n") do
      {:ok, conn} -> {:cont, conn}
      {:error, :closed} -> {:halt, conn}
    end
  end)
end
```

## PubSub Broadcasting

For multi-user applications where multiple clients see the same response:

```elixir
defmodule MyApp.ClaudeStreamer do
  def stream_to_topic(prompt, topic) do
    Task.start(fn ->
      :assistant
      |> ClaudeCode.query_stream(prompt, include_partial_messages: true)
      |> ClaudeCode.Stream.text_deltas()
      |> Enum.each(fn chunk ->
        Phoenix.PubSub.broadcast(MyApp.PubSub, topic, {:claude_chunk, chunk})
      end)

      Phoenix.PubSub.broadcast(MyApp.PubSub, topic, :claude_complete)
    end)
  end
end

# In your LiveView
def mount(_params, _session, socket) do
  Phoenix.PubSub.subscribe(MyApp.PubSub, "chat:#{socket.assigns.room_id}")
  {:ok, socket}
end

def handle_info({:claude_chunk, chunk}, socket) do
  {:noreply, assign(socket, response: socket.assigns.response <> chunk)}
end

def handle_info(:claude_complete, socket) do
  {:noreply, assign(socket, streaming: false)}
end
```

## Service Module Pattern

Wrap ClaudeCode in a service module for cleaner integration:

```elixir
defmodule MyApp.Claude do
  @moduledoc "Service wrapper for Claude interactions"

  def ask(prompt, opts \\ []) do
    session = Keyword.get(opts, :session, :assistant)
    ClaudeCode.query(session, prompt)
  end

  def stream(prompt, opts \\ []) do
    session = Keyword.get(opts, :session, :assistant)
    include_partial = Keyword.get(opts, :partial, true)

    session
    |> ClaudeCode.query_stream(prompt, include_partial_messages: include_partial)
    |> ClaudeCode.Stream.text_deltas()
  end
end

# Usage in controller/LiveView
case MyApp.Claude.ask("Hello!") do
  {:ok, response} -> # handle
  {:error, _} -> # handle
end
```

## Error Handling

Graceful error handling in LiveView:

```elixir
def handle_event("send", %{"message" => message}, socket) do
  parent = self()

  Task.start(fn ->
    try do
      :assistant
      |> ClaudeCode.query_stream(message)
      |> ClaudeCode.Stream.text_content()
      |> Enum.each(fn chunk -> send(parent, {:chunk, chunk}) end)

      send(parent, :complete)
    rescue
      e -> send(parent, {:error, Exception.message(e)})
    end
  end)

  {:noreply, assign(socket, streaming: true)}
end

def handle_info({:error, message}, socket) do
  {:noreply,
   socket
   |> put_flash(:error, "Claude error: #{message}")
   |> assign(streaming: false)}
end
```

## Next Steps

- [Streaming Guide](../guides/streaming.md) - Detailed streaming patterns
- [Supervision Guide](../advanced/supervision.md) - Production setup
- [Tool Callbacks](tool-callbacks.md) - Monitor Claude's actions
