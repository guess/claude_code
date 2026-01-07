defmodule ClaudeCode.Adapter.CLITest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.CLI

  # ============================================================================
  # shell_escape/1 Tests
  # ============================================================================

  describe "shell_escape/1" do
    test "returns simple strings unchanged" do
      assert CLI.shell_escape("hello") == "hello"
      assert CLI.shell_escape("foo123") == "foo123"
      assert CLI.shell_escape("path/to/file") == "path/to/file"
    end

    test "escapes empty strings" do
      assert CLI.shell_escape("") == "''"
    end

    test "escapes strings with spaces" do
      assert CLI.shell_escape("hello world") == "'hello world'"
      assert CLI.shell_escape("path with spaces") == "'path with spaces'"
    end

    test "escapes strings with single quotes" do
      assert CLI.shell_escape("it's") == "'it'\\''s'"
      assert CLI.shell_escape("don't") == "'don'\\''t'"
    end

    test "escapes strings with double quotes" do
      assert CLI.shell_escape("say \"hello\"") == "'say \"hello\"'"
    end

    test "escapes strings with dollar signs" do
      assert CLI.shell_escape("$HOME") == "'$HOME'"
      assert CLI.shell_escape("cost: $100") == "'cost: $100'"
    end

    test "escapes strings with backticks" do
      assert CLI.shell_escape("`command`") == "'`command`'"
    end

    test "escapes strings with backslashes" do
      assert CLI.shell_escape("path\\to\\file") == "'path\\to\\file'"
    end

    test "escapes strings with newlines" do
      assert CLI.shell_escape("line1\nline2") == "'line1\nline2'"
    end

    test "escapes strings with multiple special characters" do
      assert CLI.shell_escape("it's $100") == "'it'\\''s $100'"
      assert CLI.shell_escape("say \"hi\" to '$USER'") == "'say \"hi\" to '\\''$USER'\\'''"
    end

    test "converts non-strings to strings" do
      assert CLI.shell_escape(123) == "123"
      assert CLI.shell_escape(:atom) == "atom"
    end
  end

  # ============================================================================
  # extract_lines/1 Tests
  # ============================================================================

  describe "extract_lines/1" do
    test "extracts complete lines from buffer" do
      {lines, remaining} = CLI.extract_lines("line1\nline2\nline3\n")
      assert lines == ["line1", "line2", "line3"]
      assert remaining == ""
    end

    test "keeps incomplete line in remaining buffer" do
      {lines, remaining} = CLI.extract_lines("line1\nline2\nincomplete")
      assert lines == ["line1", "line2"]
      assert remaining == "incomplete"
    end

    test "handles empty buffer" do
      {lines, remaining} = CLI.extract_lines("")
      assert lines == []
      assert remaining == ""
    end

    test "handles buffer with no complete lines" do
      {lines, remaining} = CLI.extract_lines("partial")
      assert lines == []
      assert remaining == "partial"
    end

    test "handles buffer with single complete line" do
      {lines, remaining} = CLI.extract_lines("single\n")
      assert lines == ["single"]
      assert remaining == ""
    end

    test "handles buffer with only newline" do
      {lines, remaining} = CLI.extract_lines("\n")
      assert lines == [""]
      assert remaining == ""
    end

    test "handles buffer with multiple consecutive newlines" do
      {lines, remaining} = CLI.extract_lines("line1\n\nline3\n")
      assert lines == ["line1", "", "line3"]
      assert remaining == ""
    end

    test "handles JSON lines (typical CLI output)" do
      json1 = ~s({"type":"system","subtype":"init"})
      json2 = ~s({"type":"assistant","message":{}})
      buffer = "#{json1}\n#{json2}\n"

      {lines, remaining} = CLI.extract_lines(buffer)
      assert lines == [json1, json2]
      assert remaining == ""
    end

    test "handles partial JSON accumulation" do
      # First chunk
      {lines1, remaining1} = CLI.extract_lines(~s({"type":"sys))
      assert lines1 == []
      assert remaining1 == ~s({"type":"sys)

      # Second chunk arrives
      {lines2, remaining2} = CLI.extract_lines(remaining1 <> ~s(tem"}\n{"type":))
      assert lines2 == [~s({"type":"system"})]
      assert remaining2 == ~s({"type":)

      # Final chunk
      {lines3, remaining3} = CLI.extract_lines(remaining2 <> ~s("result"}\n))
      assert lines3 == [~s({"type":"result"})]
      assert remaining3 == ""
    end
  end

  # ============================================================================
  # Adapter Behaviour Tests
  # ============================================================================

  describe "adapter behaviour" do
    test "implements ClaudeCode.Adapter behaviour" do
      behaviours = CLI.__info__(:attributes)[:behaviour] || []
      assert ClaudeCode.Adapter in behaviours
    end
  end
end
