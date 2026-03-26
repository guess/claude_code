defmodule ClaudeCode.TestTools do
  @moduledoc false
  use ClaudeCode.MCP.Server, name: "test-tools"

  tool :add do
    description "Add two numbers"

    field(:x, :integer, required: true)
    field(:y, :integer, required: true)

    def execute(%{x: x, y: y}) do
      {:ok, "#{x + y}"}
    end
  end

  tool :greet do
    description "Greet a user"

    field(:name, :string, required: true)

    def execute(%{name: name}) do
      {:ok, "Hello, #{name}!"}
    end
  end

  tool :get_time do
    description "Get current UTC time"

    def execute(_params) do
      {:ok, to_string(DateTime.utc_now())}
    end
  end

  tool :return_map do
    description "Return structured data"

    field(:key, :string, required: true)

    def execute(%{key: key}) do
      {:ok, %{key: key, value: "data"}}
    end
  end

  tool :failing_tool do
    description "Always fails"

    def execute(_params) do
      {:error, "Something went wrong"}
    end
  end
end
