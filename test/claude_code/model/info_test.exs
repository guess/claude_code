defmodule ClaudeCode.Model.InfoTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Model.Info

  describe "new/1" do
    test "parses all fields from JSON" do
      info =
        Info.new(%{
          "value" => "claude-sonnet-4-6",
          "display_name" => "Claude Sonnet 4.6",
          "description" => "Fast and capable model",
          "supports_effort" => true,
          "supported_effort_levels" => ["low", "medium", "high"],
          "supports_adaptive_thinking" => true,
          "supports_fast_mode" => true,
          "supports_auto_mode" => true
        })

      assert info.value == "claude-sonnet-4-6"
      assert info.display_name == "Claude Sonnet 4.6"
      assert info.description == "Fast and capable model"
      assert info.supports_effort == true
      assert info.supported_effort_levels == [:low, :medium, :high]
      assert info.supports_adaptive_thinking == true
      assert info.supports_fast_mode == true
      assert info.supports_auto_mode == true
    end

    test "handles minimal fields" do
      info =
        Info.new(%{
          "value" => "claude-haiku-4-5",
          "display_name" => "Claude Haiku 4.5",
          "description" => "Fastest model"
        })

      assert info.value == "claude-haiku-4-5"
      assert info.display_name == "Claude Haiku 4.5"
      assert info.supports_effort == false
      assert info.supported_effort_levels == []
      assert info.supports_adaptive_thinking == false
      assert info.supports_fast_mode == false
      assert info.supports_auto_mode == false
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON with snake_case keys, omitting nils" do
      info =
        Info.new(%{
          "value" => "claude-sonnet-4-6",
          "display_name" => "Claude Sonnet 4.6",
          "description" => "Fast model",
          "supports_effort" => true
        })

      decoded = info |> Jason.encode!() |> Jason.decode!()

      assert decoded == %{
               "value" => "claude-sonnet-4-6",
               "display_name" => "Claude Sonnet 4.6",
               "description" => "Fast model",
               "supports_effort" => true,
               "supported_effort_levels" => [],
               "supports_adaptive_thinking" => false,
               "supports_fast_mode" => false,
               "supports_auto_mode" => false
             }
    end
  end
end
