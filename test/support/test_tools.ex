defmodule ClaudeCode.TestTools do
  @moduledoc false
  use ClaudeCode.Tool.Server, name: "test-tools"

  tool :add, "Add two numbers" do
    field(:x, :integer, required: true)
    field(:y, :integer, required: true)

    def execute(%{x: x, y: y}) do
      {:ok, "#{x + y}"}
    end
  end

  tool :greet, "Greet a user" do
    field(:name, :string, required: true)

    def execute(%{name: name}) do
      {:ok, "Hello, #{name}!"}
    end
  end

  tool :get_time, "Get current UTC time" do
    def execute(_params) do
      {:ok, to_string(DateTime.utc_now())}
    end
  end

  tool :return_map, "Return structured data" do
    field(:key, :string, required: true)

    def execute(%{key: key}) do
      {:ok, %{key: key, value: "data"}}
    end
  end

  tool :failing_tool, "Always fails" do
    def execute(_params) do
      {:error, "Something went wrong"}
    end
  end
end
