defmodule ClaudeCode.Session.SlashCommandTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Session.SlashCommand

  describe "new/1" do
    test "parses all fields from JSON map" do
      data = %{
        "name" => "commit",
        "description" => "Create a git commit",
        "argument_hint" => "<message>"
      }

      cmd = SlashCommand.new(data)

      assert cmd.name == "commit"
      assert cmd.description == "Create a git commit"
      assert cmd.argument_hint == "<message>"
    end

    test "handles missing optional fields" do
      data = %{"name" => "help", "description" => "Show help"}

      cmd = SlashCommand.new(data)

      assert cmd.name == "help"
      assert cmd.description == "Show help"
      assert cmd.argument_hint == nil
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON" do
      cmd = %SlashCommand{name: "commit", description: "Create a commit", argument_hint: "<msg>"}
      json = Jason.encode!(cmd)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "commit"
      assert decoded["description"] == "Create a commit"
      assert decoded["argument_hint"] == "<msg>"
    end
  end
end
