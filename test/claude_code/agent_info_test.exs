defmodule ClaudeCode.AgentInfoTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.AgentInfo

  describe "new/1" do
    test "parses all fields from JSON" do
      info =
        AgentInfo.new(%{
          "name" => "Explore",
          "description" => "Fast codebase exploration agent",
          "model" => "haiku"
        })

      assert info.name == "Explore"
      assert info.description == "Fast codebase exploration agent"
      assert info.model == "haiku"
    end

    test "handles missing model (inherits parent)" do
      info =
        AgentInfo.new(%{
          "name" => "code-reviewer",
          "description" => "Reviews code for issues"
        })

      assert info.name == "code-reviewer"
      assert info.description == "Reviews code for issues"
      assert info.model == nil
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON with snake_case keys, omitting nils" do
      info =
        AgentInfo.new(%{
          "name" => "Explore",
          "description" => "Explorer agent"
        })

      decoded = info |> Jason.encode!() |> Jason.decode!()

      assert decoded == %{
               "name" => "Explore",
               "description" => "Explorer agent"
             }
    end
  end
end
