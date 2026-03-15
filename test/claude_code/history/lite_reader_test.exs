defmodule ClaudeCode.History.LiteReaderTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.History.LiteReader
  alias ClaudeCode.History.SessionInfo

  @moduletag :history

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "lite_reader_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  describe "validate_uuid/1" do
    test "accepts valid UUIDs" do
      assert LiteReader.validate_uuid("550e8400-e29b-41d4-a716-446655440000") ==
               "550e8400-e29b-41d4-a716-446655440000"
    end

    test "accepts uppercase UUIDs" do
      assert LiteReader.validate_uuid("550E8400-E29B-41D4-A716-446655440000") ==
               "550E8400-E29B-41D4-A716-446655440000"
    end

    test "rejects non-UUIDs" do
      assert is_nil(LiteReader.validate_uuid("not-a-uuid"))
      assert is_nil(LiteReader.validate_uuid("session-1"))
      assert is_nil(LiteReader.validate_uuid(""))
    end
  end

  describe "read_metadata/1" do
    test "reads metadata from a session file", %{tmp_dir: tmp_dir} do
      session_id = "550e8400-e29b-41d4-a716-446655440000"
      path = Path.join(tmp_dir, "#{session_id}.jsonl")

      content = """
      {"type":"user","message":{"role":"user","content":"Hello world"},"sessionId":"#{session_id}","uuid":"u1","cwd":"/test/project","gitBranch":"main"}
      {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi!"}]},"sessionId":"#{session_id}","uuid":"a1"}
      {"type":"summary","summary":"Test conversation"}
      """

      File.write!(path, content)

      assert {:ok, %SessionInfo{} = info} = LiteReader.read_metadata(path)
      assert info.session_id == session_id
      assert info.first_prompt == "Hello world"
      assert info.cwd == "/test/project"
      assert info.git_branch == "main"
      assert info.summary == "Test conversation"
      assert info.file_size > 0
      assert info.last_modified > 0
    end

    test "extracts custom_title from tail", %{tmp_dir: tmp_dir} do
      session_id = "550e8400-e29b-41d4-a716-446655440001"
      path = Path.join(tmp_dir, "#{session_id}.jsonl")

      content = """
      {"type":"user","message":{"role":"user","content":"Hello"},"sessionId":"#{session_id}","uuid":"u1"}
      {"type":"summary","summary":"Regular summary","customTitle":"My Custom Title"}
      """

      File.write!(path, content)

      assert {:ok, %SessionInfo{} = info} = LiteReader.read_metadata(path)
      assert info.custom_title == "My Custom Title"
      assert info.summary == "My Custom Title"
    end

    test "falls back to summary then first_prompt for summary field", %{tmp_dir: tmp_dir} do
      session_id = "550e8400-e29b-41d4-a716-446655440002"
      path = Path.join(tmp_dir, "#{session_id}.jsonl")

      content = """
      {"type":"user","message":{"role":"user","content":"What is Elixir?"},"sessionId":"#{session_id}","uuid":"u1"}
      {"type":"summary","summary":"Asked about Elixir"}
      """

      File.write!(path, content)

      assert {:ok, %SessionInfo{} = info} = LiteReader.read_metadata(path)
      assert info.summary == "Asked about Elixir"
      assert info.first_prompt == "What is Elixir?"
    end

    test "skips sidechain sessions", %{tmp_dir: tmp_dir} do
      session_id = "550e8400-e29b-41d4-a716-446655440003"
      path = Path.join(tmp_dir, "#{session_id}.jsonl")

      content = """
      {"type":"user","isSidechain":true,"message":{"role":"user","content":"test"},"sessionId":"#{session_id}","uuid":"u1"}
      """

      File.write!(path, content)

      assert {:error, :sidechain} = LiteReader.read_metadata(path)
    end

    test "rejects non-UUID filenames", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "not-a-uuid.jsonl")
      File.write!(path, ~s({"type":"user","message":{"role":"user","content":"test"}}))

      assert {:error, :invalid_uuid} = LiteReader.read_metadata(path)
    end

    test "rejects empty files", %{tmp_dir: tmp_dir} do
      session_id = "550e8400-e29b-41d4-a716-446655440004"
      path = Path.join(tmp_dir, "#{session_id}.jsonl")
      File.write!(path, "")

      assert {:error, :empty_file} = LiteReader.read_metadata(path)
    end

    test "rejects sessions with no summary/title/prompt", %{tmp_dir: tmp_dir} do
      session_id = "550e8400-e29b-41d4-a716-446655440005"
      path = Path.join(tmp_dir, "#{session_id}.jsonl")

      content = """
      {"type":"queue-operation","operation":"enqueue"}
      """

      File.write!(path, content)

      assert {:error, :no_summary} = LiteReader.read_metadata(path)
    end
  end

  describe "extract_first_prompt_from_head/1" do
    test "extracts simple text prompt" do
      head = ~s({"type":"user","message":{"role":"user","content":"Hello world"},"uuid":"u1"}\n)
      assert LiteReader.extract_first_prompt_from_head(head) == "Hello world"
    end

    test "skips tool_result messages" do
      head = """
      {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"done"}]},"uuid":"u1"}
      {"type":"user","message":{"role":"user","content":"Real prompt"},"uuid":"u2"}
      """

      assert LiteReader.extract_first_prompt_from_head(head) == "Real prompt"
    end

    test "skips isMeta messages" do
      head = """
      {"type":"user","isMeta":true,"message":{"role":"user","content":"meta stuff"},"uuid":"u1"}
      {"type":"user","message":{"role":"user","content":"Real prompt"},"uuid":"u2"}
      """

      assert LiteReader.extract_first_prompt_from_head(head) == "Real prompt"
    end

    test "skips isCompactSummary messages" do
      head = """
      {"type":"user","isCompactSummary":true,"message":{"role":"user","content":"summary"},"uuid":"u1"}
      {"type":"user","message":{"role":"user","content":"After compaction"},"uuid":"u2"}
      """

      assert LiteReader.extract_first_prompt_from_head(head) == "After compaction"
    end

    test "skips auto-generated patterns" do
      head = """
      {"type":"user","message":{"role":"user","content":"<local-command-stdout>some output</local-command-stdout>"},"uuid":"u1"}
      {"type":"user","message":{"role":"user","content":"Real prompt"},"uuid":"u2"}
      """

      assert LiteReader.extract_first_prompt_from_head(head) == "Real prompt"
    end

    test "extracts command name as fallback" do
      head = """
      {"type":"user","message":{"role":"user","content":"<command-name>commit</command-name> some args"},"uuid":"u1"}
      """

      assert LiteReader.extract_first_prompt_from_head(head) == "commit"
    end

    test "truncates long prompts to 200 chars" do
      long_prompt = String.duplicate("a", 250)

      head =
        ~s({"type":"user","message":{"role":"user","content":"#{long_prompt}"},"uuid":"u1"}\n)

      result = LiteReader.extract_first_prompt_from_head(head)
      assert String.length(result) <= 201
      assert String.ends_with?(result, "\u2026")
    end

    test "returns nil when no user messages" do
      head = ~s({"type":"assistant","message":{"role":"assistant","content":"hi"},"uuid":"a1"}\n)
      assert is_nil(LiteReader.extract_first_prompt_from_head(head))
    end

    test "handles content as list of text blocks" do
      head = """
      {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Block content"}]},"uuid":"u1"}
      """

      assert LiteReader.extract_first_prompt_from_head(head) == "Block content"
    end
  end

  describe "extract_json_string_field/2" do
    test "extracts field with no space after colon" do
      text = ~s({"key":"value","other":"stuff"})
      assert LiteReader.extract_json_string_field(text, "key") == "value"
    end

    test "extracts field with space after colon" do
      text = ~s({"key": "value"})
      assert LiteReader.extract_json_string_field(text, "key") == "value"
    end

    test "returns nil for missing field" do
      text = ~s({"other":"value"})
      assert is_nil(LiteReader.extract_json_string_field(text, "key"))
    end

    test "handles escaped quotes" do
      text = ~s({"key":"value with \\"quotes\\""})
      assert LiteReader.extract_json_string_field(text, "key") == ~s(value with "quotes")
    end
  end

  describe "extract_last_json_string_field/2" do
    test "returns last occurrence" do
      text = ~s({"key":"first"}\n{"key":"second"}\n{"key":"third"})
      assert LiteReader.extract_last_json_string_field(text, "key") == "third"
    end

    test "returns nil for missing field" do
      text = ~s({"other":"value"})
      assert is_nil(LiteReader.extract_last_json_string_field(text, "key"))
    end
  end
end
