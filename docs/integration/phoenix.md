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

## LiveView with Streaming (Recommended)

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
      |> ClaudeCode.stream(message, include_partial_messages: true)
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
    try do
      response =
        :assistant
        |> ClaudeCode.stream(prompt)
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()

      json(conn, %{response: response})
    catch
      error ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: inspect(error)})
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
  |> ClaudeCode.stream(prompt)
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
      |> ClaudeCode.stream(prompt, include_partial_messages: true)
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

    session
    |> ClaudeCode.stream(prompt)
    |> ClaudeCode.Stream.text_content()
    |> Enum.join()
  end

  def stream(prompt, opts \\ []) do
    session = Keyword.get(opts, :session, :assistant)
    include_partial = Keyword.get(opts, :partial, true)

    session
    |> ClaudeCode.stream(prompt, include_partial_messages: include_partial)
    |> ClaudeCode.Stream.text_deltas()
  end
end

# Usage in controller/LiveView
response = MyApp.Claude.ask("Hello!")
# => "Hello! How can I help you today?"
```

## Error Handling

Graceful error handling in LiveView:

```elixir
def handle_event("send", %{"message" => message}, socket) do
  parent = self()

  Task.start(fn ->
    try do
      :assistant
      |> ClaudeCode.stream(message)
      |> ClaudeCode.Stream.text_content()
      |> Enum.each(fn chunk -> send(parent, {:chunk, chunk}) end)

      send(parent, :complete)
    catch
      error -> send(parent, {:error, inspect(error)})
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

- [Streaming Output](../guides/streaming-output.md) - Detailed streaming patterns
- [Hosting](../guides/hosting.md) - Production setup
- [Hooks](../guides/hooks.md) - Monitor Claude's actions
