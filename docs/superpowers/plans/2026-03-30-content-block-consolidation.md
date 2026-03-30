# Content Block Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce 13 content block struct types to 8 by merging tool use, tool result, and thinking variants into their parent structs.

**Architecture:** Variant modules (`MCPToolUseBlock`, `ServerToolUseBlock`, `MCPToolResultBlock`, `ServerToolResultBlock`, `RedactedThinkingBlock`) become `@moduledoc false` internal parsers that return the parent struct with a discriminating `:type` atom. Parser dispatch is unchanged — same keys, same routing. The public API surface shrinks from 13 to 8 content block types.

**Tech Stack:** Elixir, ExUnit

**Spec:** `docs/superpowers/specs/2026-03-30-content-block-consolidation-design.md`

---

### Task 1: Expand ToolUseBlock struct and update its tests

**Files:**
- Modify: `lib/claude_code/content/tool_use_block.ex`
- Modify: `test/claude_code/content/tool_use_block_test.exs`

- [ ] **Step 1: Update ToolUseBlock struct to support all three types**

Add `server_name` field. Widen `type` to accept `:server_tool_use` and `:mcp_tool_use`. Accept all three type strings in `new/1`. Keep `name` as string always (remove atom conversion that currently lives in `ServerToolUseBlock`).

```elixir
# lib/claude_code/content/tool_use_block.ex
defmodule ClaudeCode.Content.ToolUseBlock do
  @moduledoc """
  Represents a tool use content block within a Claude message.

  Tool use blocks indicate that Claude wants to invoke a specific tool
  with the given parameters. The `:type` field distinguishes the tool's origin:

  - `:tool_use` — agent tool (Read, Write, Bash, etc.)
  - `:server_tool_use` — Anthropic server-side tool (web_search, code_execution, etc.)
  - `:mcp_tool_use` — tool provided by an MCP server
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :id, :name, :input]
  defstruct [:type, :id, :name, :input, :caller, :server_name]

  @type tool_use_type :: :tool_use | :server_tool_use | :mcp_tool_use

  @type t :: %__MODULE__{
          type: tool_use_type(),
          id: String.t(),
          name: String.t(),
          input: map(),
          caller: map() | nil,
          server_name: String.t() | nil
        }

  @valid_types %{
    "tool_use" => :tool_use,
    "server_tool_use" => :server_tool_use,
    "mcp_tool_use" => :mcp_tool_use
  }

  @doc """
  Creates a new ToolUseBlock from JSON data.

  Accepts `"tool_use"`, `"server_tool_use"`, and `"mcp_tool_use"` type strings.
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => type_str} = data) when is_map_key(@valid_types, type_str) do
    type = @valid_types[type_str]
    required = required_fields(type)
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      {:ok,
       %__MODULE__{
         type: type,
         id: data["id"],
         name: data["name"],
         input: data["input"],
         caller: data["caller"],
         server_name: data["server_name"]
       }}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}

  defp required_fields(:mcp_tool_use), do: ["id", "name", "server_name", "input"]
  defp required_fields(_), do: ["id", "name", "input"]
end

defimpl String.Chars, for: ClaudeCode.Content.ToolUseBlock do
  def to_string(%{type: :mcp_tool_use, server_name: server, name: name}),
    do: "[mcp: #{server}/#{name}]"

  def to_string(%{type: :server_tool_use, name: name}), do: "[server tool: #{name}]"
  def to_string(%{type: :tool_use, name: name}), do: "[tool: #{name}]"
end
```

- [ ] **Step 2: Update ToolUseBlock tests for new types**

Add test cases for `:server_tool_use` and `:mcp_tool_use` parsing directly through `ToolUseBlock.new/1`. Keep existing `:tool_use` tests unchanged.

```elixir
# Add these describe blocks to test/claude_code/content/tool_use_block_test.exs

  describe "new/1 with server_tool_use" do
    test "creates a server tool use block" do
      data = %{
        "type" => "server_tool_use",
        "id" => "srvtoolu_123",
        "name" => "web_search",
        "input" => %{"query" => "elixir programming"}
      }

      assert {:ok, block} = ToolUseBlock.new(data)
      assert block.type == :server_tool_use
      assert block.id == "srvtoolu_123"
      assert block.name == "web_search"
      assert block.input == %{"query" => "elixir programming"}
      assert block.caller == nil
      assert block.server_name == nil
    end

    test "keeps server tool names as strings" do
      for name <- ~w(web_search web_fetch code_execution bash_code_execution text_editor_code_execution) do
        data = %{"type" => "server_tool_use", "id" => "srvtoolu_test", "name" => name, "input" => %{}}
        assert {:ok, block} = ToolUseBlock.new(data)
        assert is_binary(block.name)
      end
    end

    test "parses caller field when present" do
      data = %{
        "type" => "server_tool_use",
        "id" => "srvtoolu_456",
        "name" => "code_execution",
        "input" => %{"code" => "print('hello')"},
        "caller" => %{"type" => "direct"}
      }

      assert {:ok, block} = ToolUseBlock.new(data)
      assert block.caller == %{"type" => "direct"}
    end
  end

  describe "new/1 with mcp_tool_use" do
    test "creates an MCP tool use block" do
      data = %{
        "type" => "mcp_tool_use",
        "id" => "mcptoolu_123",
        "name" => "read_file",
        "server_name" => "filesystem",
        "input" => %{"path" => "/tmp/test.txt"}
      }

      assert {:ok, block} = ToolUseBlock.new(data)
      assert block.type == :mcp_tool_use
      assert block.id == "mcptoolu_123"
      assert block.name == "read_file"
      assert block.server_name == "filesystem"
      assert block.input == %{"path" => "/tmp/test.txt"}
    end

    test "returns error when server_name is missing" do
      data = %{"type" => "mcp_tool_use", "id" => "x", "name" => "y", "input" => %{}}
      assert {:error, {:missing_fields, [:server_name]}} = ToolUseBlock.new(data)
    end
  end

  describe "String.Chars" do
    test "formats tool_use" do
      block = %ToolUseBlock{type: :tool_use, id: "1", name: "Read", input: %{}}
      assert to_string(block) == "[tool: Read]"
    end

    test "formats server_tool_use" do
      block = %ToolUseBlock{type: :server_tool_use, id: "1", name: "web_search", input: %{}}
      assert to_string(block) == "[server tool: web_search]"
    end

    test "formats mcp_tool_use" do
      block = %ToolUseBlock{type: :mcp_tool_use, id: "1", name: "read_file", input: %{}, server_name: "filesystem"}
      assert to_string(block) == "[mcp: filesystem/read_file]"
    end
  end
```

- [ ] **Step 3: Run ToolUseBlock tests**

Run: `cd /Users/steve/repos/strates/claude_code && mix test test/claude_code/content/tool_use_block_test.exs -v`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add lib/claude_code/content/tool_use_block.ex test/claude_code/content/tool_use_block_test.exs
git commit -m "feat: expand ToolUseBlock to support server_tool_use and mcp_tool_use types"
```

---

### Task 2: Expand ToolResultBlock struct and update its tests

**Files:**
- Modify: `lib/claude_code/content/tool_result_block.ex`
- Modify: `test/claude_code/content/tool_result_block_test.exs`

- [ ] **Step 1: Update ToolResultBlock struct to support all three types**

Add `caller` field. Widen `type` to accept `:server_tool_result` and `:mcp_tool_result`. The 6 server tool result type strings all map to `:server_tool_result`.

```elixir
# lib/claude_code/content/tool_result_block.ex
defmodule ClaudeCode.Content.ToolResultBlock do
  @moduledoc """
  Represents a tool result content block within a Claude message.

  Tool result blocks contain the output from a tool execution. The `:type`
  field distinguishes the result's origin:

  - `:tool_result` — result from an agent tool
  - `:server_tool_result` — result from an Anthropic server-side tool
  - `:mcp_tool_result` — result from an MCP server tool
  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.CLI.Parser

  @enforce_keys [:type, :tool_use_id, :content]
  defstruct [:type, :tool_use_id, :content, :is_error, :caller]

  @type tool_result_type :: :tool_result | :server_tool_result | :mcp_tool_result

  @type t :: %__MODULE__{
          type: tool_result_type(),
          tool_use_id: String.t(),
          content: String.t() | [ClaudeCode.Content.t()],
          is_error: boolean() | nil,
          caller: map() | nil
        }

  @type_mapping %{
    "tool_result" => :tool_result,
    "mcp_tool_result" => :mcp_tool_result,
    "web_search_tool_result" => :server_tool_result,
    "web_fetch_tool_result" => :server_tool_result,
    "code_execution_tool_result" => :server_tool_result,
    "bash_code_execution_tool_result" => :server_tool_result,
    "text_editor_code_execution_tool_result" => :server_tool_result,
    "tool_search_tool_result" => :server_tool_result
  }

  @doc """
  Creates a new ToolResultBlock from JSON data.

  Accepts `"tool_result"`, `"mcp_tool_result"`, and all server tool result
  type strings (which map to `:server_tool_result`).
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => type_str} = data) when is_map_key(@type_mapping, type_str) do
    type = @type_mapping[type_str]
    required = required_fields(type)
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      case parse_content(type, data["content"]) do
        {:ok, parsed_content} ->
          {:ok,
           %__MODULE__{
             type: type,
             tool_use_id: data["tool_use_id"],
             content: parsed_content,
             is_error: parse_is_error(type, data),
             caller: data["caller"]
           }}

        {:error, _} = error ->
          error
      end
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}

  defp required_fields(:mcp_tool_result), do: ["tool_use_id", "content", "is_error"]
  defp required_fields(_), do: ["tool_use_id", "content"]

  defp parse_is_error(:server_tool_result, _data), do: nil
  defp parse_is_error(_type, data), do: Map.get(data, "is_error", false)

  defp parse_content(:server_tool_result, content), do: {:ok, content}
  defp parse_content(_type, content) when is_binary(content), do: {:ok, content}
  defp parse_content(_type, content) when is_list(content), do: Parser.parse_contents(content)
  defp parse_content(_type, _), do: {:error, :invalid_content}
end

defimpl String.Chars, for: ClaudeCode.Content.ToolResultBlock do
  def to_string(%{type: :server_tool_result}), do: "[server tool result]"

  def to_string(%{content: content}) when is_binary(content), do: content

  def to_string(%{content: blocks}) when is_list(blocks),
    do: Enum.map_join(blocks, &Kernel.to_string/1)
end
```

- [ ] **Step 2: Update ToolResultBlock tests for new types**

Add test cases for `:server_tool_result` and `:mcp_tool_result`. Keep existing `:tool_result` tests unchanged.

```elixir
# Add these describe blocks to test/claude_code/content/tool_result_block_test.exs

  describe "new/1 with server_tool_result" do
    test "parses all server tool result types to :server_tool_result" do
      for type <- ~w(web_search_tool_result web_fetch_tool_result code_execution_tool_result
                     bash_code_execution_tool_result text_editor_code_execution_tool_result
                     tool_search_tool_result) do
        data = %{
          "type" => type,
          "tool_use_id" => "toolu_#{type}",
          "content" => [%{"type" => "web_search_result", "url" => "https://example.com"}]
        }

        assert {:ok, block} = ToolResultBlock.new(data)
        assert block.type == :server_tool_result
        assert block.tool_use_id == "toolu_#{type}"
        assert block.is_error == nil
      end
    end

    test "preserves opaque content for server tool results" do
      data = %{
        "type" => "web_search_tool_result",
        "tool_use_id" => "toolu_search",
        "content" => %{"type" => "web_search_tool_result_error", "error_code" => "unavailable"}
      }

      assert {:ok, block} = ToolResultBlock.new(data)
      assert block.content == %{"type" => "web_search_tool_result_error", "error_code" => "unavailable"}
    end

    test "includes optional caller field" do
      data = %{
        "type" => "web_search_tool_result",
        "tool_use_id" => "toolu_search",
        "content" => [%{"type" => "web_search_result"}],
        "caller" => %{"type" => "direct_caller", "tool_use_id" => "toolu_parent"}
      }

      assert {:ok, block} = ToolResultBlock.new(data)
      assert block.caller == %{"type" => "direct_caller", "tool_use_id" => "toolu_parent"}
    end
  end

  describe "new/1 with mcp_tool_result" do
    test "creates an MCP tool result block with string content" do
      data = %{
        "type" => "mcp_tool_result",
        "tool_use_id" => "mcptoolu_123",
        "content" => "file contents here",
        "is_error" => false
      }

      assert {:ok, block} = ToolResultBlock.new(data)
      assert block.type == :mcp_tool_result
      assert block.tool_use_id == "mcptoolu_123"
      assert block.content == "file contents here"
      assert block.is_error == false
    end

    test "creates an MCP tool result block with text block array content" do
      data = %{
        "type" => "mcp_tool_result",
        "tool_use_id" => "mcptoolu_456",
        "content" => [%{"type" => "text", "text" => "result text"}],
        "is_error" => false
      }

      assert {:ok, block} = ToolResultBlock.new(data)
      assert [%ClaudeCode.Content.TextBlock{text: "result text"}] = block.content
    end

    test "requires is_error field" do
      data = %{"type" => "mcp_tool_result", "tool_use_id" => "x", "content" => "y"}
      assert {:error, {:missing_fields, [:is_error]}} = ToolResultBlock.new(data)
    end
  end

  describe "String.Chars" do
    test "formats tool_result with string content" do
      block = %ToolResultBlock{type: :tool_result, tool_use_id: "1", content: "hello", is_error: false}
      assert to_string(block) == "hello"
    end

    test "formats server_tool_result" do
      block = %ToolResultBlock{type: :server_tool_result, tool_use_id: "1", content: [%{"type" => "result"}]}
      assert to_string(block) == "[server tool result]"
    end

    test "formats mcp_tool_result with string content" do
      block = %ToolResultBlock{type: :mcp_tool_result, tool_use_id: "1", content: "result text", is_error: false}
      assert to_string(block) == "result text"
    end
  end
```

- [ ] **Step 3: Run ToolResultBlock tests**

Run: `cd /Users/steve/repos/strates/claude_code && mix test test/claude_code/content/tool_result_block_test.exs -v`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add lib/claude_code/content/tool_result_block.ex test/claude_code/content/tool_result_block_test.exs
git commit -m "feat: expand ToolResultBlock to support server_tool_result and mcp_tool_result types"
```

---

### Task 3: Expand ThinkingBlock struct and update its tests

**Files:**
- Modify: `lib/claude_code/content/thinking_block.ex`
- Modify: `test/claude_code/content/thinking_block_test.exs`

- [ ] **Step 1: Update ThinkingBlock struct to support redacted thinking**

Add `data` field. Relax `@enforce_keys` so `thinking` and `signature` can be nil for redacted. Accept `"redacted_thinking"` type string.

```elixir
# lib/claude_code/content/thinking_block.ex
defmodule ClaudeCode.Content.ThinkingBlock do
  @moduledoc """
  Represents a thinking content block within a Claude message.

  Thinking blocks contain Claude's extended reasoning, visible when
  extended thinking is enabled on supported models.

  - `:thinking` — visible reasoning with `thinking` text and `signature`
  - `:redacted_thinking` — encrypted reasoning with `data` blob; `thinking` and `signature` are nil
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type]
  defstruct [:type, :thinking, :signature, :data]

  @type thinking_type :: :thinking | :redacted_thinking

  @type t :: %__MODULE__{
          type: thinking_type(),
          thinking: String.t() | nil,
          signature: String.t() | nil,
          data: String.t() | nil
        }

  @doc """
  Creates a new ThinkingBlock from JSON data.

  Accepts `"thinking"` and `"redacted_thinking"` type strings.
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "thinking"} = data) do
    required = ["thinking", "signature"]
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      {:ok,
       %__MODULE__{
         type: :thinking,
         thinking: data["thinking"],
         signature: data["signature"]
       }}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(%{"type" => "redacted_thinking"} = data) do
    required = ["data"]
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      {:ok, %__MODULE__{type: :redacted_thinking, data: data["data"]}}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}
end

defimpl String.Chars, for: ClaudeCode.Content.ThinkingBlock do
  def to_string(%{type: :redacted_thinking}), do: "[redacted thinking]"
  def to_string(%{thinking: thinking}), do: thinking
end
```

- [ ] **Step 2: Update ThinkingBlock tests for redacted thinking**

```elixir
# Add these describe blocks to test/claude_code/content/thinking_block_test.exs

  describe "new/1 with redacted_thinking" do
    test "creates a redacted thinking block" do
      data = %{"type" => "redacted_thinking", "data" => "encrypted_abc123"}

      assert {:ok, block} = ThinkingBlock.new(data)
      assert block.type == :redacted_thinking
      assert block.data == "encrypted_abc123"
      assert block.thinking == nil
      assert block.signature == nil
    end

    test "returns error for missing data field" do
      assert {:error, {:missing_fields, [:data]}} =
               ThinkingBlock.new(%{"type" => "redacted_thinking"})
    end
  end

  describe "String.Chars" do
    test "renders thinking as text" do
      block = %ThinkingBlock{type: :thinking, thinking: "reasoning", signature: "sig_1"}
      assert to_string(block) == "reasoning"
    end

    test "renders redacted thinking as placeholder" do
      block = %ThinkingBlock{type: :redacted_thinking, data: "encrypted"}
      assert to_string(block) == "[redacted thinking]"
    end
  end
```

- [ ] **Step 3: Run ThinkingBlock tests**

Run: `cd /Users/steve/repos/strates/claude_code && mix test test/claude_code/content/thinking_block_test.exs -v`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add lib/claude_code/content/thinking_block.ex test/claude_code/content/thinking_block_test.exs
git commit -m "feat: expand ThinkingBlock to support redacted_thinking type"
```

---

### Task 4: Convert variant modules to `@moduledoc false` parsers

**Files:**
- Modify: `lib/claude_code/content/mcp_tool_use_block.ex`
- Modify: `lib/claude_code/content/server_tool_use_block.ex`
- Modify: `lib/claude_code/content/mcp_tool_result_block.ex`
- Modify: `lib/claude_code/content/server_tool_result_block.ex`
- Modify: `lib/claude_code/content/redacted_thinking_block.ex`

- [ ] **Step 1: Convert MCPToolUseBlock to delegating parser**

```elixir
# lib/claude_code/content/mcp_tool_use_block.ex
defmodule ClaudeCode.Content.MCPToolUseBlock do
  @moduledoc false
  # Internal parser for mcp_tool_use content blocks.
  # Returns %ToolUseBlock{type: :mcp_tool_use}.

  alias ClaudeCode.Content.ToolUseBlock

  @spec new(map()) :: {:ok, ToolUseBlock.t()} | {:error, atom() | {:missing_fields, [atom()]}}
  defdelegate new(data), to: ToolUseBlock
end
```

- [ ] **Step 2: Convert ServerToolUseBlock to delegating parser**

```elixir
# lib/claude_code/content/server_tool_use_block.ex
defmodule ClaudeCode.Content.ServerToolUseBlock do
  @moduledoc false
  # Internal parser for server_tool_use content blocks.
  # Returns %ToolUseBlock{type: :server_tool_use}.

  alias ClaudeCode.Content.ToolUseBlock

  @spec new(map()) :: {:ok, ToolUseBlock.t()} | {:error, atom() | {:missing_fields, [atom()]}}
  defdelegate new(data), to: ToolUseBlock
end
```

- [ ] **Step 3: Convert MCPToolResultBlock to delegating parser**

```elixir
# lib/claude_code/content/mcp_tool_result_block.ex
defmodule ClaudeCode.Content.MCPToolResultBlock do
  @moduledoc false
  # Internal parser for mcp_tool_result content blocks.
  # Returns %ToolResultBlock{type: :mcp_tool_result}.

  alias ClaudeCode.Content.ToolResultBlock

  @spec new(map()) :: {:ok, ToolResultBlock.t()} | {:error, atom() | {:missing_fields, [atom()]}}
  defdelegate new(data), to: ToolResultBlock
end
```

- [ ] **Step 4: Convert ServerToolResultBlock to delegating parser**

```elixir
# lib/claude_code/content/server_tool_result_block.ex
defmodule ClaudeCode.Content.ServerToolResultBlock do
  @moduledoc false
  # Internal parser for server tool result content blocks.
  # Returns %ToolResultBlock{type: :server_tool_result}.

  alias ClaudeCode.Content.ToolResultBlock

  @spec new(map()) :: {:ok, ToolResultBlock.t()} | {:error, atom() | {:missing_fields, [atom()]}}
  defdelegate new(data), to: ToolResultBlock
end
```

- [ ] **Step 5: Convert RedactedThinkingBlock to delegating parser**

```elixir
# lib/claude_code/content/redacted_thinking_block.ex
defmodule ClaudeCode.Content.RedactedThinkingBlock do
  @moduledoc false
  # Internal parser for redacted_thinking content blocks.
  # Returns %ThinkingBlock{type: :redacted_thinking}.

  alias ClaudeCode.Content.ThinkingBlock

  @spec new(map()) :: {:ok, ThinkingBlock.t()} | {:error, atom() | {:missing_fields, [atom()]}}
  defdelegate new(data), to: ThinkingBlock
end
```

- [ ] **Step 6: Run full test suite to check for compilation errors**

Run: `cd /Users/steve/repos/strates/claude_code && mix test --no-start 2>&1 | head -50`
Expected: Compiles without errors. Some tests may fail (expected — they still reference old struct types).

- [ ] **Step 7: Commit**

```bash
git add lib/claude_code/content/mcp_tool_use_block.ex lib/claude_code/content/server_tool_use_block.ex lib/claude_code/content/mcp_tool_result_block.ex lib/claude_code/content/server_tool_result_block.ex lib/claude_code/content/redacted_thinking_block.ex
git commit -m "refactor: convert variant content blocks to @moduledoc false delegating parsers"
```

---

### Task 5: Update Content module

**Files:**
- Modify: `lib/claude_code/content.ex`
- Modify: `test/claude_code/content_test.exs`

- [ ] **Step 1: Simplify Content module**

Remove aliases for the 5 variant modules. Reduce `content?/1` and `content_type/1` to 8 clauses. Update the `t()` type union. Remove `ServerToolResultBlock.server_tool_result_type()` from `content_type/1` return type.

```elixir
# lib/claude_code/content.ex
defmodule ClaudeCode.Content do
  @moduledoc """
  Utilities for working with content blocks in Claude messages.

  Content blocks can be text, thinking, tool use requests, tool results,
  images, documents, compaction summaries, or container uploads.
  This module provides functions to parse and work with any content type.
  """

  alias ClaudeCode.Content.CompactionBlock
  alias ClaudeCode.Content.ContainerUploadBlock
  alias ClaudeCode.Content.DocumentBlock
  alias ClaudeCode.Content.ImageBlock
  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ThinkingBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock

  @type t ::
          TextBlock.t()
          | ThinkingBlock.t()
          | ToolUseBlock.t()
          | ToolResultBlock.t()
          | ImageBlock.t()
          | DocumentBlock.t()
          | ContainerUploadBlock.t()
          | CompactionBlock.t()

  @doc """
  Checks if a value is any type of content block.
  """
  @spec content?(any()) :: boolean()
  def content?(%TextBlock{}), do: true
  def content?(%ThinkingBlock{}), do: true
  def content?(%ToolUseBlock{}), do: true
  def content?(%ToolResultBlock{}), do: true
  def content?(%ImageBlock{}), do: true
  def content?(%DocumentBlock{}), do: true
  def content?(%ContainerUploadBlock{}), do: true
  def content?(%CompactionBlock{}), do: true
  def content?(_), do: false

  @type delta ::
          %{type: :text_delta, text: String.t()}
          | %{type: :input_json_delta, partial_json: String.t()}
          | %{type: :thinking_delta, thinking: String.t()}
          | %{type: :signature_delta, signature: String.t()}
          | %{type: :citations_delta, citation: map()}
          | %{type: :compaction_delta, content: String.t() | nil}

  @doc """
  Parses a content block delta from a stream event into a typed map.

  ## Examples

      iex> ClaudeCode.Content.parse_delta(%{"type" => "text_delta", "text" => "Hi"})
      {:ok, %{type: :text_delta, text: "Hi"}}

      iex> ClaudeCode.Content.parse_delta(%{"type" => "future_delta"})
      {:error, {:unknown_delta_type, "future_delta"}}

  """
  @spec parse_delta(map()) :: {:ok, delta()} | {:error, term()}
  def parse_delta(%{"type" => "text_delta", "text" => text}), do: {:ok, %{type: :text_delta, text: text}}

  def parse_delta(%{"type" => "input_json_delta", "partial_json" => json}),
    do: {:ok, %{type: :input_json_delta, partial_json: json}}

  def parse_delta(%{"type" => "thinking_delta", "thinking" => thinking}),
    do: {:ok, %{type: :thinking_delta, thinking: thinking}}

  def parse_delta(%{"type" => "signature_delta", "signature" => signature}),
    do: {:ok, %{type: :signature_delta, signature: signature}}

  def parse_delta(%{"type" => "citations_delta", "citation" => citation}),
    do: {:ok, %{type: :citations_delta, citation: citation}}

  def parse_delta(%{"type" => "compaction_delta", "content" => content}),
    do: {:ok, %{type: :compaction_delta, content: content}}

  def parse_delta(%{"type" => type}), do: {:error, {:unknown_delta_type, type}}

  def parse_delta(_), do: {:error, :missing_type}

  @doc """
  Returns the type of a content block.
  """
  @spec content_type(t()) ::
          :text
          | :thinking
          | :redacted_thinking
          | :tool_use
          | :server_tool_use
          | :mcp_tool_use
          | :tool_result
          | :server_tool_result
          | :mcp_tool_result
          | :image
          | :document
          | :container_upload
          | :compaction
  def content_type(%TextBlock{type: type}), do: type
  def content_type(%ThinkingBlock{type: type}), do: type
  def content_type(%ToolUseBlock{type: type}), do: type
  def content_type(%ToolResultBlock{type: type}), do: type
  def content_type(%ImageBlock{type: type}), do: type
  def content_type(%DocumentBlock{type: type}), do: type
  def content_type(%ContainerUploadBlock{type: type}), do: type
  def content_type(%CompactionBlock{type: type}), do: type
end
```

- [ ] **Step 2: Add variant type tests to content_test.exs**

```elixir
# Add to the "type detection" describe block in test/claude_code/content_test.exs

    test "content?/1 returns true for variant types via parent struct" do
      server_tool_use = %ToolUseBlock{type: :server_tool_use, id: "1", name: "web_search", input: %{}}
      mcp_tool_use = %ToolUseBlock{type: :mcp_tool_use, id: "1", name: "read", input: %{}, server_name: "fs"}
      server_result = %ToolResultBlock{type: :server_tool_result, tool_use_id: "1", content: []}
      mcp_result = %ToolResultBlock{type: :mcp_tool_result, tool_use_id: "1", content: "ok", is_error: false}
      redacted = %ThinkingBlock{type: :redacted_thinking, data: "encrypted"}

      assert Content.content?(server_tool_use)
      assert Content.content?(mcp_tool_use)
      assert Content.content?(server_result)
      assert Content.content?(mcp_result)
      assert Content.content?(redacted)
    end

# Add to the "content type helpers" describe block

    test "content_type/1 returns variant types" do
      assert Content.content_type(%ToolUseBlock{type: :server_tool_use, id: "1", name: "web_search", input: %{}}) ==
               :server_tool_use

      assert Content.content_type(%ToolUseBlock{type: :mcp_tool_use, id: "1", name: "read", input: %{}, server_name: "fs"}) ==
               :mcp_tool_use

      assert Content.content_type(%ToolResultBlock{type: :server_tool_result, tool_use_id: "1", content: []}) ==
               :server_tool_result

      assert Content.content_type(%ToolResultBlock{type: :mcp_tool_result, tool_use_id: "1", content: "ok", is_error: false}) ==
               :mcp_tool_result

      assert Content.content_type(%ThinkingBlock{type: :redacted_thinking, data: "encrypted"}) ==
               :redacted_thinking
    end
```

- [ ] **Step 3: Run Content tests**

Run: `cd /Users/steve/repos/strates/claude_code && mix test test/claude_code/content_test.exs -v`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add lib/claude_code/content.ex test/claude_code/content_test.exs
git commit -m "refactor: simplify Content module to 8 struct types"
```

---

### Task 6: Update Stream module

**Files:**
- Modify: `lib/claude_code/stream.ex`

- [ ] **Step 1: Update thinking_content/1 to handle redacted thinking blocks**

Change the `thinking_content/1` function at line 101-109 to skip nil thinking values instead of crashing on redacted blocks:

```elixir
# In lib/claude_code/stream.ex, replace thinking_content/1 (lines 101-109)

  @spec thinking_content(Enumerable.t()) :: Enumerable.t()
  def thinking_content(stream) do
    stream
    |> Stream.filter(&match?(%Message.AssistantMessage{}, &1))
    |> Stream.flat_map(fn %Message.AssistantMessage{message: message} ->
      message.content
      |> Enum.filter(&match?(%Content.ThinkingBlock{}, &1))
      |> Enum.flat_map(fn
        %{thinking: thinking} when is_binary(thinking) -> [thinking]
        _ -> []
      end)
    end)
  end
```

No other Stream functions need changes — `tool_uses/1`, `tool_results_by_name/2`, and `collect/1` already match on `%ToolUseBlock{}` and `%ToolResultBlock{}` which now cover all variants.

- [ ] **Step 2: Run Stream tests**

Run: `cd /Users/steve/repos/strates/claude_code && mix test test/claude_code/stream_test.exs -v`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add lib/claude_code/stream.ex
git commit -m "fix: handle redacted thinking blocks in Stream.thinking_content/1"
```

---

### Task 7: Update variant test files and parser tests

**Files:**
- Modify: `test/claude_code/content/mcp_tool_use_block_test.exs`
- Modify: `test/claude_code/content/server_tool_use_block_test.exs`
- Modify: `test/claude_code/content/mcp_tool_result_block_test.exs`
- Modify: `test/claude_code/content/server_tool_result_block_test.exs`
- Modify: `test/claude_code/content/redacted_thinking_block_test.exs`
- Modify: `test/claude_code/cli/parser_test.exs`

- [ ] **Step 1: Update variant test files to assert parent structs**

The variant modules now delegate to parent structs. Update all assertions from `%MCPToolUseBlock{}` to `%ToolUseBlock{type: :mcp_tool_use}` etc. These tests now verify that the delegation works correctly.

```elixir
# test/claude_code/content/mcp_tool_use_block_test.exs
defmodule ClaudeCode.Content.MCPToolUseBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.MCPToolUseBlock
  alias ClaudeCode.Content.ToolUseBlock

  describe "new/1" do
    test "creates a ToolUseBlock with mcp_tool_use type" do
      data = %{
        "type" => "mcp_tool_use",
        "id" => "mcptoolu_123",
        "name" => "read_file",
        "server_name" => "filesystem",
        "input" => %{"path" => "/tmp/test.txt"}
      }

      assert {:ok, %ToolUseBlock{} = block} = MCPToolUseBlock.new(data)
      assert block.type == :mcp_tool_use
      assert block.id == "mcptoolu_123"
      assert block.name == "read_file"
      assert block.server_name == "filesystem"
      assert block.input == %{"path" => "/tmp/test.txt"}
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, [:id, :name, :server_name, :input]}} =
               MCPToolUseBlock.new(%{"type" => "mcp_tool_use"})

      assert {:error, {:missing_fields, [:server_name]}} =
               MCPToolUseBlock.new(%{"type" => "mcp_tool_use", "id" => "x", "name" => "y", "input" => %{}})
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_content_type} =
               MCPToolUseBlock.new(%{
                 "type" => "text",
                 "id" => "x",
                 "name" => "y",
                 "server_name" => "z",
                 "input" => %{}
               })
    end
  end
end
```

```elixir
# test/claude_code/content/server_tool_use_block_test.exs
defmodule ClaudeCode.Content.ServerToolUseBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ServerToolUseBlock
  alias ClaudeCode.Content.ToolUseBlock

  describe "new/1" do
    test "creates a ToolUseBlock with server_tool_use type" do
      data = %{
        "type" => "server_tool_use",
        "id" => "srvtoolu_123",
        "name" => "web_search",
        "input" => %{"query" => "elixir programming"}
      }

      assert {:ok, %ToolUseBlock{} = block} = ServerToolUseBlock.new(data)
      assert block.type == :server_tool_use
      assert block.id == "srvtoolu_123"
      assert block.name == "web_search"
      assert block.input == %{"query" => "elixir programming"}
      assert block.caller == nil
    end

    test "keeps all tool names as strings" do
      for name <- ~w(web_search web_fetch code_execution bash_code_execution text_editor_code_execution) do
        data = %{"type" => "server_tool_use", "id" => "srvtoolu_test", "name" => name, "input" => %{}}
        assert {:ok, %ToolUseBlock{} = block} = ServerToolUseBlock.new(data)
        assert is_binary(block.name)
      end
    end

    test "parses caller field when present" do
      data = %{
        "type" => "server_tool_use",
        "id" => "srvtoolu_456",
        "name" => "code_execution",
        "input" => %{"code" => "print('hello')"},
        "caller" => %{"type" => "direct"}
      }

      assert {:ok, %ToolUseBlock{} = block} = ServerToolUseBlock.new(data)
      assert block.caller == %{"type" => "direct"}
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, [:id, :name, :input]}} =
               ServerToolUseBlock.new(%{"type" => "server_tool_use"})
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_content_type} =
               ServerToolUseBlock.new(%{"type" => "text", "id" => "x", "name" => "y", "input" => %{}})
    end
  end
end
```

```elixir
# test/claude_code/content/mcp_tool_result_block_test.exs
defmodule ClaudeCode.Content.MCPToolResultBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.MCPToolResultBlock
  alias ClaudeCode.Content.ToolResultBlock

  describe "new/1" do
    test "creates a ToolResultBlock with mcp_tool_result type and string content" do
      data = %{
        "type" => "mcp_tool_result",
        "tool_use_id" => "mcptoolu_123",
        "content" => "file contents here",
        "is_error" => false
      }

      assert {:ok, %ToolResultBlock{} = block} = MCPToolResultBlock.new(data)
      assert block.type == :mcp_tool_result
      assert block.tool_use_id == "mcptoolu_123"
      assert block.content == "file contents here"
      assert block.is_error == false
    end

    test "creates a ToolResultBlock with text block array content" do
      data = %{
        "type" => "mcp_tool_result",
        "tool_use_id" => "mcptoolu_456",
        "content" => [%{"type" => "text", "text" => "result text"}],
        "is_error" => false
      }

      assert {:ok, %ToolResultBlock{} = block} = MCPToolResultBlock.new(data)
      assert [%ClaudeCode.Content.TextBlock{text: "result text"}] = block.content
    end

    test "creates a ToolResultBlock with error" do
      data = %{
        "type" => "mcp_tool_result",
        "tool_use_id" => "mcptoolu_789",
        "content" => "tool execution failed",
        "is_error" => true
      }

      assert {:ok, %ToolResultBlock{} = block} = MCPToolResultBlock.new(data)
      assert block.is_error == true
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, [:tool_use_id, :content, :is_error]}} =
               MCPToolResultBlock.new(%{"type" => "mcp_tool_result"})
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_content_type} =
               MCPToolResultBlock.new(%{
                 "type" => "text",
                 "tool_use_id" => "x",
                 "content" => "y",
                 "is_error" => false
               })
    end
  end
end
```

```elixir
# test/claude_code/content/server_tool_result_block_test.exs
defmodule ClaudeCode.Content.ServerToolResultBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ServerToolResultBlock
  alias ClaudeCode.Content.ToolResultBlock

  @known_types ~w(
    web_search_tool_result
    web_fetch_tool_result
    code_execution_tool_result
    bash_code_execution_tool_result
    text_editor_code_execution_tool_result
    tool_search_tool_result
  )

  describe "new/1" do
    test "parses all known server tool result types to :server_tool_result" do
      for type <- @known_types do
        data = %{
          "type" => type,
          "tool_use_id" => "toolu_#{type}",
          "content" => [%{"type" => "web_search_result", "url" => "https://example.com"}]
        }

        assert {:ok, %ToolResultBlock{} = block} = ServerToolResultBlock.new(data)
        assert block.type == :server_tool_result
        assert block.tool_use_id == "toolu_#{type}"
        assert block.content == data["content"]
        assert block.caller == nil
        assert block.is_error == nil
      end
    end

    test "preserves opaque content" do
      data = %{
        "type" => "web_search_tool_result",
        "tool_use_id" => "toolu_search",
        "content" => %{"type" => "web_search_tool_result_error", "error_code" => "unavailable"}
      }

      assert {:ok, %ToolResultBlock{} = block} = ServerToolResultBlock.new(data)
      assert block.type == :server_tool_result
      assert block.content == %{"type" => "web_search_tool_result_error", "error_code" => "unavailable"}
    end

    test "includes optional caller field" do
      data = %{
        "type" => "web_search_tool_result",
        "tool_use_id" => "toolu_search",
        "content" => [%{"type" => "web_search_result"}],
        "caller" => %{"type" => "direct_caller", "tool_use_id" => "toolu_parent"}
      }

      assert {:ok, %ToolResultBlock{} = block} = ServerToolResultBlock.new(data)
      assert block.caller == %{"type" => "direct_caller", "tool_use_id" => "toolu_parent"}
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, missing}} =
               ServerToolResultBlock.new(%{"type" => "web_search_tool_result"})

      assert :tool_use_id in missing
      assert :content in missing
    end

    test "returns error for unknown type" do
      assert {:error, :invalid_content_type} =
               ServerToolResultBlock.new(%{"type" => "unknown_tool_result"})
    end
  end
end
```

```elixir
# test/claude_code/content/redacted_thinking_block_test.exs
defmodule ClaudeCode.Content.RedactedThinkingBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.RedactedThinkingBlock
  alias ClaudeCode.Content.ThinkingBlock

  describe "new/1" do
    test "creates a ThinkingBlock with redacted_thinking type" do
      data = %{"type" => "redacted_thinking", "data" => "encrypted_abc123"}

      assert {:ok, %ThinkingBlock{} = block} = RedactedThinkingBlock.new(data)
      assert block.type == :redacted_thinking
      assert block.data == "encrypted_abc123"
      assert block.thinking == nil
      assert block.signature == nil
    end

    test "returns error for missing data field" do
      assert {:error, {:missing_fields, [:data]}} =
               RedactedThinkingBlock.new(%{"type" => "redacted_thinking"})
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_content_type} =
               RedactedThinkingBlock.new(%{"type" => "thinking", "data" => "abc"})
    end
  end

  describe "String.Chars" do
    test "renders as placeholder text" do
      block = %ThinkingBlock{type: :redacted_thinking, data: "abc"}
      assert to_string(block) == "[redacted thinking]"
    end
  end
end
```

- [ ] **Step 2: Update parser_test.exs assertions**

In `test/claude_code/cli/parser_test.exs`, update the aliases and assertions:

Remove these aliases:
```elixir
  alias ClaudeCode.Content.MCPToolResultBlock
  alias ClaudeCode.Content.MCPToolUseBlock
  alias ClaudeCode.Content.RedactedThinkingBlock
  alias ClaudeCode.Content.ServerToolResultBlock
  alias ClaudeCode.Content.ServerToolUseBlock
```

Update assertions (find and replace):

- `%RedactedThinkingBlock{data: "encrypted_data_abc"}` → `%ThinkingBlock{type: :redacted_thinking, data: "encrypted_data_abc"}`
- `%ServerToolUseBlock{id: "srvtoolu_123", name: :web_search}` → `%ToolUseBlock{type: :server_tool_use, id: "srvtoolu_123", name: "web_search"}` (note: name is now a string)
- `%MCPToolUseBlock{name: "read_file", server_name: "filesystem"}` → `%ToolUseBlock{type: :mcp_tool_use, name: "read_file", server_name: "filesystem"}`
- `%MCPToolResultBlock{tool_use_id: "mcptoolu_123", is_error: false}` → `%ToolResultBlock{type: :mcp_tool_result, tool_use_id: "mcptoolu_123", is_error: false}`
- `%ServerToolResultBlock{tool_use_id: "toolu_" <> ^type}` → `%ToolResultBlock{type: :server_tool_result, tool_use_id: "toolu_" <> ^type}`
- Update the test description `"parses server tool result blocks via unified ServerToolResultBlock"` → `"parses server tool result blocks to ToolResultBlock"`

- [ ] **Step 3: Run all updated tests**

Run: `cd /Users/steve/repos/strates/claude_code && mix test test/claude_code/content/ test/claude_code/cli/parser_test.exs -v`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add test/claude_code/content/ test/claude_code/cli/parser_test.exs
git commit -m "test: update variant and parser tests to assert parent structs"
```

---

### Task 8: Update JSONEncoder tests

**Files:**
- Modify: `test/claude_code/json_encoder_test.exs`

- [ ] **Step 1: Update JSONEncoder test assertions**

Replace `%ServerToolResultBlock{...}` with `%ToolResultBlock{type: :server_tool_result, ...}`. Update alias from `ServerToolResultBlock` to use `ToolResultBlock`. The JSON encoding should still produce the correct type strings (e.g., `:server_tool_result` encodes as `"server_tool_result"`).

Replace alias:
```elixir
  # Remove:
  alias ClaudeCode.Content.ServerToolResultBlock
  # Already present:
  alias ClaudeCode.Content.ToolResultBlock
```

Replace the two Jason `ServerToolResultBlock` tests:
```elixir
    test "encodes server_tool_result ToolResultBlock" do
      block = %ToolResultBlock{
        type: :server_tool_result,
        tool_use_id: "toolu_search",
        content: [%{"type" => "web_search_result", "url" => "https://example.com"}],
        caller: %{"type" => "direct_caller"}
      }

      json = Jason.encode!(block)

      assert json =~ ~s("type":"server_tool_result")
      assert json =~ ~s("tool_use_id":"toolu_search")
      assert json =~ ~s("caller")
    end

    test "encodes server_tool_result ToolResultBlock excluding nil caller" do
      block = %ToolResultBlock{
        type: :server_tool_result,
        tool_use_id: "toolu_exec",
        content: %{"type" => "code_execution_result", "stdout" => "hello"}
      }

      json = Jason.encode!(block)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "server_tool_result"
      assert decoded["tool_use_id"] == "toolu_exec"
      refute Map.has_key?(decoded, "caller")
    end
```

Replace the JSON module `ServerToolResultBlock` test:
```elixir
    test "encodes server_tool_result ToolResultBlock" do
      block = %ToolResultBlock{
        type: :server_tool_result,
        tool_use_id: "toolu_fetch",
        content: %{"type" => "web_fetch", "url" => "https://example.com"}
      }

      json = JSON.encode!(block)

      assert json =~ "\"type\":"
      assert json =~ "\"tool_use_id\":"
    end
```

- [ ] **Step 2: Run JSONEncoder tests**

Run: `cd /Users/steve/repos/strates/claude_code && mix test test/claude_code/json_encoder_test.exs -v`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add test/claude_code/json_encoder_test.exs
git commit -m "test: update JSONEncoder tests for consolidated content blocks"
```

---

### Task 9: Run full quality checks and fix any remaining references

**Files:**
- Possibly modify: `lib/claude_code/test/factory.ex` (if it references variant types)
- Modify: `.claude/skills/cli-sync/references/type-mapping.md`

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/steve/repos/strates/claude_code && mix test`
Expected: All tests PASS. If any fail, fix the remaining references to old struct types.

- [ ] **Step 2: Run quality checks**

Run: `cd /Users/steve/repos/strates/claude_code && mix quality`
Expected: All checks pass (compile, format, credo, dialyzer).

- [ ] **Step 3: Fix any remaining failures**

If `mix test` or `mix quality` surface additional references to old struct types (e.g., in other test files, the `Test` module, or factory), update them:
- `%MCPToolUseBlock{}` → `%ToolUseBlock{type: :mcp_tool_use}`
- `%ServerToolUseBlock{}` → `%ToolUseBlock{type: :server_tool_use}`
- `%MCPToolResultBlock{}` → `%ToolResultBlock{type: :mcp_tool_result}`
- `%ServerToolResultBlock{}` → `%ToolResultBlock{type: :server_tool_result}`
- `%RedactedThinkingBlock{}` → `%ThinkingBlock{type: :redacted_thinking}`

For `ServerToolUseBlock` name assertions, change atom matches to string: `:web_search` → `"web_search"`.

- [ ] **Step 4: Commit fixes if any**

```bash
git add -A
git commit -m "fix: resolve remaining references to old variant struct types"
```

---

### Task 10: Update type-mapping.md

**Files:**
- Modify: `.claude/skills/cli-sync/references/type-mapping.md`

- [ ] **Step 1: Update the Content Block Types table**

Replace the content block table in `type-mapping.md` with:

```markdown
## Content Block Types

Content blocks come from the Anthropic API types (`BetaContentBlock` in TS SDK). The CLI passes
these through in assistant/user message `content` arrays. The Anthropic API type definitions are
in `captured/anthropic-api-messages.d.ts`.

| Elixir Module | Anthropic API Type (TS) | Python SDK Type | Notes |
|---|---|---|---|
| `Content.TextBlock` | `BetaTextBlock` | `TextBlock` | |
| `Content.ThinkingBlock` | `BetaThinkingBlock` | `ThinkingBlock` | `type: :thinking` |
| `Content.ThinkingBlock` | `BetaRedactedThinkingBlock` | -- | `type: :redacted_thinking`; parsed via `Content.RedactedThinkingBlock` (`@moduledoc false`) |
| `Content.ToolUseBlock` | `BetaToolUseBlock` | `ToolUseBlock` | `type: :tool_use` |
| `Content.ToolUseBlock` | `BetaServerToolUseBlock` | -- | `type: :server_tool_use`; parsed via `Content.ServerToolUseBlock` (`@moduledoc false`) |
| `Content.ToolUseBlock` | `BetaMCPToolUseBlock` | -- | `type: :mcp_tool_use`; parsed via `Content.MCPToolUseBlock` (`@moduledoc false`) |
| `Content.ToolResultBlock` | `BetaToolResultBlockParam` | `ToolResultBlock` | `type: :tool_result`; round-tripped in user messages |
| `Content.ToolResultBlock` | *(various: `BetaWebSearchToolResultBlock`, `BetaCodeExecutionToolResultBlock`, etc.)* | -- | `type: :server_tool_result`; parsed via `Content.ServerToolResultBlock` (`@moduledoc false`) |
| `Content.ToolResultBlock` | `BetaMCPToolResultBlock` | -- | `type: :mcp_tool_result`; parsed via `Content.MCPToolResultBlock` (`@moduledoc false`) |
| `Content.ImageBlock` | `BetaImageBlockParam` | -- | Input-only (user messages) |
| `Content.DocumentBlock` | `BetaDocumentBlock` / `BetaRequestDocumentBlock` | -- | PDF/text documents |
| `Content.ContainerUploadBlock` | `BetaContainerUploadBlock` | -- | Code execution container files |
| `Content.CompactionBlock` | `BetaCompactionBlock` | -- | Context compaction summaries |
```

- [ ] **Step 2: Update the Lookup by TS SDK Name table**

Update the reverse index entries for the consolidated types:

```markdown
| `BetaMCPToolResultBlock` | `Content.ToolResultBlock` (type: `:mcp_tool_result`) |
| `BetaMCPToolUseBlock` | `Content.ToolUseBlock` (type: `:mcp_tool_use`) |
| `BetaRedactedThinkingBlock` | `Content.ThinkingBlock` (type: `:redacted_thinking`) |
| `BetaServerToolUseBlock` | `Content.ToolUseBlock` (type: `:server_tool_use`) |
```

Remove the standalone entries for:
- `Content.MCPToolResultBlock`
- `Content.MCPToolUseBlock`
- `Content.RedactedThinkingBlock`
- `Content.ServerToolUseBlock`

(These modules still exist but are `@moduledoc false` internal parsers.)

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/cli-sync/references/type-mapping.md
git commit -m "docs: update type-mapping.md for content block consolidation"
```

---

### Task 11: Final verification

- [ ] **Step 1: Run full test suite one more time**

Run: `cd /Users/steve/repos/strates/claude_code && mix test`
Expected: All tests PASS

- [ ] **Step 2: Run quality checks**

Run: `cd /Users/steve/repos/strates/claude_code && mix quality`
Expected: All checks pass

- [ ] **Step 3: Verify docs generate cleanly**

Run: `cd /Users/steve/repos/strates/claude_code && mix docs 2>&1 | grep -i warning | head -20`
Expected: No warnings related to the consolidated content block types. The variant modules should not appear in generated docs.

- [ ] **Step 4: Final commit if needed**

If any fixes were required, commit them. Otherwise this step is a no-op.
