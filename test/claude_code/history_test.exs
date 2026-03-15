defmodule ClaudeCode.HistoryTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.History
  alias ClaudeCode.History.SessionMessage

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

    test "reads and parses a JSONL file into raw maps", %{tmp_dir: tmp_dir} do
      session_file = Path.join(tmp_dir, "test-session.jsonl")

      content = """
      {"type":"user","message":{"role":"user","content":"Hello"},"sessionId":"test-123","uuid":"u1"}
      {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi there!"}],"model":"claude-3","id":"msg_1"},"sessionId":"test-123","uuid":"a1"}
      """

      File.write!(session_file, content)

      assert {:ok, entries} = History.read_file(session_file)
      assert length(entries) == 2

      assert %{"type" => "user", "session_id" => "test-123"} = Enum.at(entries, 0)
      assert %{"type" => "assistant", "session_id" => "test-123"} = Enum.at(entries, 1)
    end

    test "preserves all entry types including non-message types", %{tmp_dir: tmp_dir} do
      session_file = Path.join(tmp_dir, "all-types.jsonl")

      content = """
      {"type":"summary","summary":"Test conversation"}
      {"type":"queue-operation","operation":"enqueue"}
      {"type":"user","message":{"role":"user","content":"Hello"},"sessionId":"test-123","uuid":"u1"}
      """

      File.write!(session_file, content)

      assert {:ok, entries} = History.read_file(session_file)
      assert length(entries) == 3

      assert %{"type" => "summary"} = Enum.at(entries, 0)
      assert %{"type" => "queue-operation"} = Enum.at(entries, 1)
      assert %{"type" => "user"} = Enum.at(entries, 2)
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

  describe "list_sessions/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_list_test_#{:rand.uniform(1_000_000)}")
      projects_dir = Path.join(tmp_dir, "projects")
      project_dir = Path.join(projects_dir, History.sanitize_path("/test/project"))
      File.mkdir_p!(project_dir)

      # Create session files with valid UUIDs and content
      ids = [
        "550e8400-e29b-41d4-a716-446655440001",
        "550e8400-e29b-41d4-a716-446655440002",
        "550e8400-e29b-41d4-a716-446655440003"
      ]

      for {id, idx} <- Enum.with_index(ids) do
        content =
          ~s({"type":"user","message":{"role":"user","content":"Prompt #{idx}"},"sessionId":"#{id}","uuid":"u#{idx}","cwd":"/test/project"}\n{"type":"summary","summary":"Session #{idx}"})

        File.write!(Path.join(project_dir, "#{id}.jsonl"), content)
      end

      # Create a non-jsonl file that should be ignored
      File.write!(Path.join(project_dir, "other.txt"), "ignore me")

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, claude_dir: tmp_dir, session_ids: ids}
    end

    test "lists sessions with metadata for a directory", %{claude_dir: claude_dir, session_ids: ids} do
      assert {:ok, sessions} =
               History.list_sessions(
                 project_path: "/test/project",
                 claude_dir: claude_dir,
                 include_worktrees: false
               )

      assert length(sessions) == 3
      returned_ids = sessions |> Enum.map(& &1.session_id) |> Enum.sort()
      assert returned_ids == Enum.sort(ids)

      # All sessions should have summaries
      Enum.each(sessions, fn s ->
        assert is_binary(s.summary)
        assert s.file_size > 0
        assert s.last_modified > 0
      end)
    end

    test "lists all sessions across all projects", %{claude_dir: claude_dir} do
      assert {:ok, sessions} = History.list_sessions(claude_dir: claude_dir)
      assert length(sessions) == 3
    end

    test "respects limit option", %{claude_dir: claude_dir} do
      assert {:ok, sessions} =
               History.list_sessions(
                 project_path: "/test/project",
                 claude_dir: claude_dir,
                 include_worktrees: false,
                 limit: 2
               )

      assert length(sessions) == 2
    end

    test "returns empty list for non-existent project", %{claude_dir: claude_dir} do
      assert {:ok, []} =
               History.list_sessions(
                 project_path: "/nonexistent",
                 claude_dir: claude_dir,
                 include_worktrees: false
               )
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

  describe "sanitize_path/1" do
    test "replaces non-alphanumeric chars with hyphens" do
      assert History.sanitize_path("/Users/me/project") == "-Users-me-project"
    end

    test "handles underscores and dots" do
      assert History.sanitize_path("/Users/me/my_project.ex") == "-Users-me-my-project-ex"
    end

    test "truncates and hashes long paths" do
      long_path = "/" <> String.duplicate("a", 250)
      result = History.sanitize_path(long_path)
      # Should be truncated to 200 chars + "-" + hash
      assert String.length(result) > 200
      assert String.length(result) < 250
    end
  end

  describe "simple_hash/1" do
    test "returns deterministic hash" do
      assert History.simple_hash("test") == History.simple_hash("test")
    end

    test "returns base36 string" do
      hash = History.simple_hash("test")
      assert Regex.match?(~r/^[0-9a-z]+$/, hash)
    end
  end

  describe "get_messages/2" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_getmsg_test_#{:rand.uniform(1_000_000)}")
      projects_dir = Path.join(tmp_dir, "projects")
      project_dir = Path.join(projects_dir, History.sanitize_path("/test/project"))
      File.mkdir_p!(project_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, claude_dir: tmp_dir, project_dir: project_dir}
    end

    test "returns chain-built messages in order with parsed content", %{
      claude_dir: claude_dir,
      project_dir: project_dir
    } do
      session_id = "550e8400-e29b-41d4-a716-446655440010"
      session_file = Path.join(project_dir, "#{session_id}.jsonl")

      content = """
      {"type":"user","uuid":"u1","parentUuid":null,"sessionId":"#{session_id}","message":{"role":"user","content":"Hello"}}
      {"type":"assistant","uuid":"a1","parentUuid":"u1","sessionId":"#{session_id}","message":{"role":"assistant","content":[{"type":"text","text":"Hi!"}]}}
      {"type":"user","uuid":"u2","parentUuid":"a1","sessionId":"#{session_id}","message":{"role":"user","content":"How are you?"}}
      """

      File.write!(session_file, content)

      assert {:ok, messages} =
               History.get_messages(session_id,
                 project_path: "/test/project",
                 claude_dir: claude_dir
               )

      assert length(messages) == 3

      # All are SessionMessage structs
      assert [%SessionMessage{}, %SessionMessage{}, %SessionMessage{}] = messages

      # Check ordering and metadata
      assert Enum.at(messages, 0).uuid == "u1"
      assert Enum.at(messages, 0).type == :user
      assert Enum.at(messages, 0).session_id == session_id
      assert Enum.at(messages, 1).uuid == "a1"
      assert Enum.at(messages, 1).type == :assistant
      assert Enum.at(messages, 2).uuid == "u2"

      # User message content is parsed
      assert %{content: "Hello", role: :user} = Enum.at(messages, 0).message

      # Assistant message content has parsed TextBlock
      assistant_msg = Enum.at(messages, 1).message
      assert [%ClaudeCode.Content.TextBlock{text: "Hi!"}] = assistant_msg.content
    end

    test "supports limit and offset", %{claude_dir: claude_dir, project_dir: project_dir} do
      session_id = "550e8400-e29b-41d4-a716-446655440011"
      session_file = Path.join(project_dir, "#{session_id}.jsonl")

      content = """
      {"type":"user","uuid":"u1","parentUuid":null,"sessionId":"#{session_id}","message":{"role":"user","content":"A"}}
      {"type":"assistant","uuid":"a1","parentUuid":"u1","sessionId":"#{session_id}","message":{"content":"B"}}
      {"type":"user","uuid":"u2","parentUuid":"a1","sessionId":"#{session_id}","message":{"role":"user","content":"C"}}
      {"type":"assistant","uuid":"a2","parentUuid":"u2","sessionId":"#{session_id}","message":{"content":"D"}}
      """

      File.write!(session_file, content)

      assert {:ok, page} =
               History.get_messages(session_id,
                 project_path: "/test/project",
                 claude_dir: claude_dir,
                 limit: 2,
                 offset: 1
               )

      assert length(page) == 2
      assert Enum.at(page, 0).uuid == "a1"
      assert Enum.at(page, 1).uuid == "u2"
    end

    test "returns empty list for invalid UUID" do
      assert {:ok, []} = History.get_messages("not-a-uuid")
    end

    test "returns empty list for non-existent session", %{claude_dir: claude_dir} do
      assert {:ok, []} =
               History.get_messages("550e8400-e29b-41d4-a716-446655440099",
                 project_path: "/test/project",
                 claude_dir: claude_dir
               )
    end

    test "filters out sidechain and meta messages", %{claude_dir: claude_dir, project_dir: project_dir} do
      session_id = "550e8400-e29b-41d4-a716-446655440012"
      session_file = Path.join(project_dir, "#{session_id}.jsonl")

      content = """
      {"type":"user","uuid":"u1","parentUuid":null,"sessionId":"#{session_id}","message":{"content":"Main"}}
      {"type":"assistant","uuid":"a1","parentUuid":"u1","sessionId":"#{session_id}","isMeta":true,"message":{"content":"Meta"}}
      {"type":"assistant","uuid":"a2","parentUuid":"u1","sessionId":"#{session_id}","message":{"content":"Reply"}}
      """

      File.write!(session_file, content)

      assert {:ok, messages} =
               History.get_messages(session_id,
                 project_path: "/test/project",
                 claude_dir: claude_dir
               )

      # a1 is meta so filtered out; chain goes u1 -> a2 (latest non-meta leaf)
      types = Enum.map(messages, & &1.type)
      assert :user in types
      assert :assistant in types
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
      session_id = "550e8400-e29b-41d4-a716-446655440099"
      session_file = Path.join(project_dir, "#{session_id}.jsonl")

      content = """
      {"type":"queue-operation","operation":"dequeue","timestamp":"2026-01-06T17:46:07.839Z","sessionId":"#{session_id}"}
      {"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"/test/project","sessionId":"#{session_id}","version":"2.0.76","gitBranch":"main","type":"user","message":{"role":"user","content":"What is Elixir?"},"uuid":"u1","timestamp":"2026-01-06T17:46:07.844Z"}
      {"parentUuid":"u1","isSidechain":false,"userType":"external","cwd":"/test/project","sessionId":"#{session_id}","version":"2.0.76","gitBranch":"main","message":{"model":"claude-opus-4-5-20251101","id":"msg_01Test","type":"message","role":"assistant","content":[{"type":"text","text":"Elixir is a functional programming language."}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":100,"output_tokens":50}},"requestId":"req_test","type":"assistant","uuid":"a1","timestamp":"2026-01-06T17:46:11.406Z"}
      """

      File.write!(session_file, content)

      # Test read_session (returns all raw entries including queue-operation)
      assert {:ok, entries} = History.read_session(session_id, claude_dir: claude_dir)
      assert length(entries) == 3
      assert %{"type" => "queue-operation"} = Enum.at(entries, 0)

      # Test get_messages (chain-built, parsed into SessionMessage structs)
      assert {:ok, messages} =
               History.get_messages(session_id,
                 project_path: "/test/project",
                 claude_dir: claude_dir
               )

      assert length(messages) == 2

      # Verify user message
      [user_msg, assistant_msg] = messages
      assert %SessionMessage{type: :user, message: %{content: "What is Elixir?"}} = user_msg

      # Verify assistant message with parsed content block
      assert %SessionMessage{type: :assistant} = assistant_msg
      assert [text_block] = assistant_msg.message.content
      assert text_block.text == "Elixir is a functional programming language."
    end
  end
end
