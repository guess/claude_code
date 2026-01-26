defmodule ClaudeCode.HistoryTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.History
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.UserMessage

  @moduletag :history

  describe "encode_project_path/1" do
    test "encodes absolute path" do
      assert History.encode_project_path("/Users/me/project") == "-Users-me-project"
    end

    test "handles nested paths" do
      assert History.encode_project_path("/Users/me/repos/my-project") ==
               "-Users-me-repos-my-project"
    end

    test "encodes underscores as hyphens" do
      assert History.encode_project_path("/Users/me/my_project") == "-Users-me-my-project"
    end

    test "encodes both slashes and underscores" do
      assert History.encode_project_path("/Users/me/repos/claude_code") ==
               "-Users-me-repos-claude-code"
    end
  end

  describe "decode_project_path/1" do
    test "decodes encoded path" do
      assert History.decode_project_path("-Users-me-project") == "/Users/me/project"
    end

    test "handles nested paths" do
      # Note: encoding is lossy - dashes in path become slashes
      assert History.decode_project_path("-Users-me-repos-my-project") ==
               "/Users/me/repos/my/project"
    end

    test "roundtrips correctly for paths without dashes" do
      # Only paths without dashes roundtrip perfectly
      original = "/Users/me/repos/project"
      encoded = History.encode_project_path(original)
      decoded = History.decode_project_path(encoded)
      assert decoded == original
    end

    test "encoding is lossy for paths with dashes" do
      # Paths with dashes cannot roundtrip - dashes become slashes
      original = "/Users/me/repos/my-project"
      encoded = History.encode_project_path(original)
      assert encoded == "-Users-me-repos-my-project"
      # Decoding treats all dashes as path separators
      decoded = History.decode_project_path(encoded)
      assert decoded == "/Users/me/repos/my/project"
      assert decoded != original
    end

    test "encoding is lossy for paths with underscores" do
      # Paths with underscores cannot roundtrip - underscores become hyphens then slashes
      original = "/Users/me/repos/my_project"
      encoded = History.encode_project_path(original)
      assert encoded == "-Users-me-repos-my-project"
      # Decoding treats all dashes as path separators
      decoded = History.decode_project_path(encoded)
      assert decoded == "/Users/me/repos/my/project"
      assert decoded != original
    end
  end

  describe "read_file/1 with test fixtures" do
    setup do
      # Create a temporary directory with test JSONL files
      tmp_dir = Path.join(System.tmp_dir!(), "claude_history_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "reads and parses a JSONL file", %{tmp_dir: tmp_dir} do
      session_file = Path.join(tmp_dir, "test-session.jsonl")

      content = """
      {"type":"summary","summary":"Test conversation"}
      {"type":"user","message":{"role":"user","content":"Hello"},"sessionId":"test-123","uuid":"u1"}
      {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi there!"}],"model":"claude-3","id":"msg_1"},"sessionId":"test-123","uuid":"a1"}
      """

      File.write!(session_file, content)

      assert {:ok, entries} = History.read_file(session_file)
      assert length(entries) == 3

      # Check summary
      assert %{"type" => "summary", "summary" => "Test conversation"} = Enum.at(entries, 0)

      # Check user message (keys should be normalized)
      user_entry = Enum.at(entries, 1)
      assert user_entry["type"] == "user"
      assert user_entry["session_id"] == "test-123"

      # Check assistant message
      assistant_entry = Enum.at(entries, 2)
      assert assistant_entry["type"] == "assistant"
      assert assistant_entry["session_id"] == "test-123"
    end

    test "normalizes camelCase keys to snake_case", %{tmp_dir: tmp_dir} do
      session_file = Path.join(tmp_dir, "camel-case.jsonl")

      content = """
      {"type":"user","sessionId":"s1","parentUuid":"p1","gitBranch":"main","message":{"role":"user","content":"test"}}
      """

      File.write!(session_file, content)

      assert {:ok, [entry]} = History.read_file(session_file)
      assert entry["session_id"] == "s1"
      assert entry["parent_uuid"] == "p1"
      assert entry["git_branch"] == "main"
      # Original camelCase keys should not exist
      refute Map.has_key?(entry, "sessionId")
      refute Map.has_key?(entry, "parentUuid")
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_read_error, :enoent, _}} =
               History.read_file("/nonexistent/path.jsonl")
    end

    test "returns error for invalid JSON", %{tmp_dir: tmp_dir} do
      session_file = Path.join(tmp_dir, "invalid.jsonl")
      File.write!(session_file, "not valid json\n")

      assert {:error, {:json_decode_error, 0, _}} = History.read_file(session_file)
    end
  end

  describe "conversation_from_file/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_conv_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "extracts user and assistant messages", %{tmp_dir: tmp_dir} do
      session_file = Path.join(tmp_dir, "conversation.jsonl")

      content = """
      {"type":"summary","summary":"Test"}
      {"type":"queue-operation","operation":"enqueue"}
      {"type":"user","message":{"role":"user","content":"What is 2+2?"},"sessionId":"test-123","uuid":"u1"}
      {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"4"}],"model":"claude-3","id":"msg_1"},"sessionId":"test-123","uuid":"a1"}
      {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"done"}]},"sessionId":"test-123","uuid":"u2"}
      """

      File.write!(session_file, content)

      assert {:ok, messages} = History.conversation_from_file(session_file)

      # Should only have user and assistant messages
      assert length(messages) == 3

      # First is user message with string content
      assert %UserMessage{message: %{content: "What is 2+2?"}} = Enum.at(messages, 0)

      # Second is assistant message with text block
      assert %AssistantMessage{message: %{content: [text_block]}} = Enum.at(messages, 1)
      assert text_block.text == "4"

      # Third is user message with tool result
      assert %UserMessage{message: %{content: [tool_result]}} = Enum.at(messages, 2)
      assert tool_result.tool_use_id == "t1"
    end

    test "filters out non-conversation messages", %{tmp_dir: tmp_dir} do
      session_file = Path.join(tmp_dir, "mixed.jsonl")

      content = """
      {"type":"summary","summary":"Test"}
      {"type":"system","subtype":"api_error","error":"timeout"}
      {"type":"file-history-snapshot","snapshot":{}}
      {"type":"user","message":{"role":"user","content":"Hello"},"sessionId":"test-123","uuid":"u1"}
      """

      File.write!(session_file, content)

      assert {:ok, messages} = History.conversation_from_file(session_file)
      assert length(messages) == 1
      assert %UserMessage{} = hd(messages)
    end
  end

  describe "find_session_path/2" do
    setup do
      # Create a mock .claude directory structure
      tmp_dir = Path.join(System.tmp_dir!(), "claude_find_test_#{:rand.uniform(1_000_000)}")
      projects_dir = Path.join(tmp_dir, "projects")
      project_dir = Path.join(projects_dir, "-test-project")
      File.mkdir_p!(project_dir)

      # Create a session file
      session_id = "abc123-def456"
      session_file = Path.join(project_dir, "#{session_id}.jsonl")
      File.write!(session_file, ~s({"type":"summary","summary":"test"}))

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, claude_dir: tmp_dir, session_id: session_id, expected_path: session_file}
    end

    test "finds session file by ID", %{
      claude_dir: claude_dir,
      session_id: session_id,
      expected_path: expected_path
    } do
      assert {:ok, ^expected_path} =
               History.find_session_path(session_id, claude_dir: claude_dir)
    end

    test "returns error for non-existent session", %{claude_dir: claude_dir} do
      assert {:error, {:session_not_found, "nonexistent"}} =
               History.find_session_path("nonexistent", claude_dir: claude_dir)
    end

    test "searches specific project path", %{claude_dir: claude_dir, session_id: session_id} do
      assert {:ok, _path} =
               History.find_session_path(session_id,
                 claude_dir: claude_dir,
                 project_path: "/test/project"
               )
    end
  end

  describe "list_sessions/2" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_list_test_#{:rand.uniform(1_000_000)}")
      projects_dir = Path.join(tmp_dir, "projects")
      project_dir = Path.join(projects_dir, "-test-project")
      File.mkdir_p!(project_dir)

      # Create multiple session files
      for id <- ["session-1", "session-2", "session-3"] do
        File.write!(Path.join(project_dir, "#{id}.jsonl"), "{}")
      end

      # Create a non-jsonl file that should be ignored
      File.write!(Path.join(project_dir, "other.txt"), "ignore me")

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, claude_dir: tmp_dir}
    end

    test "lists all session IDs for a project", %{claude_dir: claude_dir} do
      assert {:ok, sessions} = History.list_sessions("/test/project", claude_dir: claude_dir)
      assert sessions == ["session-1", "session-2", "session-3"]
    end

    test "returns error for non-existent project", %{claude_dir: claude_dir} do
      assert {:error, {:project_not_found, :enoent, "/nonexistent"}} =
               History.list_sessions("/nonexistent", claude_dir: claude_dir)
    end
  end

  describe "list_projects/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_projects_test_#{:rand.uniform(1_000_000)}")
      projects_dir = Path.join(tmp_dir, "projects")

      # Create multiple project directories
      for project <- ["-Users-test-project1", "-Users-test-project2"] do
        File.mkdir_p!(Path.join(projects_dir, project))
      end

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, claude_dir: tmp_dir}
    end

    test "lists all projects", %{claude_dir: claude_dir} do
      assert {:ok, projects} = History.list_projects(claude_dir: claude_dir)
      assert "/Users/test/project1" in projects
      assert "/Users/test/project2" in projects
    end
  end

  describe "summary/2" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_summary_test_#{:rand.uniform(1_000_000)}")
      projects_dir = Path.join(tmp_dir, "projects")
      project_dir = Path.join(projects_dir, "-test-project")
      File.mkdir_p!(project_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, claude_dir: tmp_dir, project_dir: project_dir}
    end

    test "returns summary when present", %{claude_dir: claude_dir, project_dir: project_dir} do
      session_file = Path.join(project_dir, "with-summary.jsonl")

      File.write!(session_file, """
      {"type":"summary","summary":"User asked about Elixir patterns"}
      {"type":"user","message":{"role":"user","content":"test"},"sessionId":"with-summary"}
      """)

      assert {:ok, "User asked about Elixir patterns"} =
               History.summary("with-summary", claude_dir: claude_dir)
    end

    test "returns nil when no summary", %{claude_dir: claude_dir, project_dir: project_dir} do
      session_file = Path.join(project_dir, "no-summary.jsonl")

      File.write!(session_file, """
      {"type":"user","message":{"role":"user","content":"test"},"sessionId":"no-summary"}
      """)

      assert {:ok, nil} = History.summary("no-summary", claude_dir: claude_dir)
    end
  end

  describe "integration with real session format" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_real_test_#{:rand.uniform(1_000_000)}")
      projects_dir = Path.join(tmp_dir, "projects")
      project_dir = Path.join(projects_dir, "-test-project")
      File.mkdir_p!(project_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, claude_dir: tmp_dir, project_dir: project_dir}
    end

    test "parses realistic session file format", %{
      claude_dir: claude_dir,
      project_dir: project_dir
    } do
      # This mimics the actual format from ~/.claude/projects/
      session_file = Path.join(project_dir, "real-session.jsonl")

      content = """
      {"type":"queue-operation","operation":"dequeue","timestamp":"2026-01-06T17:46:07.839Z","sessionId":"real-session"}
      {"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"/test/project","sessionId":"real-session","version":"2.0.76","gitBranch":"main","type":"user","message":{"role":"user","content":"What is Elixir?"},"uuid":"u1","timestamp":"2026-01-06T17:46:07.844Z"}
      {"parentUuid":"u1","isSidechain":false,"userType":"external","cwd":"/test/project","sessionId":"real-session","version":"2.0.76","gitBranch":"main","message":{"model":"claude-opus-4-5-20251101","id":"msg_01Test","type":"message","role":"assistant","content":[{"type":"text","text":"Elixir is a functional programming language."}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":100,"output_tokens":50}},"requestId":"req_test","type":"assistant","uuid":"a1","timestamp":"2026-01-06T17:46:11.406Z"}
      """

      File.write!(session_file, content)

      # Test read_session
      assert {:ok, entries} = History.read_session("real-session", claude_dir: claude_dir)
      assert length(entries) == 3

      # Test conversation
      assert {:ok, messages} = History.conversation("real-session", claude_dir: claude_dir)
      assert length(messages) == 2

      # Verify user message
      [user_msg, assistant_msg] = messages
      assert %UserMessage{message: %{content: "What is Elixir?"}} = user_msg

      # Verify assistant message
      assert %AssistantMessage{message: %{content: [text_block]}} = assistant_msg
      assert text_block.text == "Elixir is a functional programming language."
    end
  end
end
