defmodule ClaudeCode.AgentTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Agent

  describe "new/1" do
    test "creates agent with only required name" do
      agent = Agent.new(name: "reviewer")

      assert %Agent{
               name: "reviewer",
               description: nil,
               prompt: nil,
               model: nil,
               tools: nil
             } = agent
    end

    test "creates agent with all fields" do
      agent =
        Agent.new(
          name: "code-reviewer",
          description: "Expert code reviewer",
          prompt: "You review code for quality.",
          model: "haiku",
          tools: ["View", "Grep", "Glob"]
        )

      assert agent.name == "code-reviewer"
      assert agent.description == "Expert code reviewer"
      assert agent.prompt == "You review code for quality."
      assert agent.model == "haiku"
      assert agent.tools == ["View", "Grep", "Glob"]
    end

    test "raises when name is missing" do
      assert_raise KeyError, ~r/:name/, fn ->
        Agent.new(prompt: "test")
      end
    end
  end

  describe "to_agents_map/1" do
    test "converts a single agent to CLI map format" do
      agents = [Agent.new(name: "reviewer", prompt: "Review code.", model: "haiku")]

      assert Agent.to_agents_map(agents) == %{
               "reviewer" => %{"prompt" => "Review code.", "model" => "haiku"}
             }
    end

    test "converts multiple agents" do
      agents = [
        Agent.new(name: "reviewer", description: "Reviews code", prompt: "Review."),
        Agent.new(name: "planner", prompt: "Plan.", tools: ["View"])
      ]

      result = Agent.to_agents_map(agents)

      assert result == %{
               "reviewer" => %{"description" => "Reviews code", "prompt" => "Review."},
               "planner" => %{"prompt" => "Plan.", "tools" => ["View"]}
             }
    end

    test "omits nil fields from config map" do
      agents = [Agent.new(name: "minimal")]

      assert Agent.to_agents_map(agents) == %{"minimal" => %{}}
    end

    test "includes all non-nil fields" do
      agents = [
        Agent.new(
          name: "full",
          description: "Full agent",
          prompt: "Do everything.",
          model: "opus",
          tools: ["Bash", "View"]
        )
      ]

      assert Agent.to_agents_map(agents) == %{
               "full" => %{
                 "description" => "Full agent",
                 "prompt" => "Do everything.",
                 "model" => "opus",
                 "tools" => ["Bash", "View"]
               }
             }
    end
  end

  describe "options integration" do
    test "agent structs are accepted by session options validation" do
      agents = [
        Agent.new(
          name: "reviewer",
          description: "Reviews code",
          prompt: "You review code.",
          model: "haiku"
        )
      ]

      assert {:ok, validated} = ClaudeCode.Options.validate_session_options(agents: agents)

      assert validated[:agents] == %{
               "reviewer" => %{
                 "description" => "Reviews code",
                 "prompt" => "You review code.",
                 "model" => "haiku"
               }
             }
    end

    test "agent structs are accepted by query options validation" do
      agents = [Agent.new(name: "planner", prompt: "Plan things.")]

      assert {:ok, validated} = ClaudeCode.Options.validate_query_options(agents: agents)
      assert validated[:agents] == %{"planner" => %{"prompt" => "Plan things."}}
    end

    test "raw map format still works" do
      agents = %{
        "reviewer" => %{"description" => "Reviews", "prompt" => "Review."}
      }

      assert {:ok, validated} = ClaudeCode.Options.validate_session_options(agents: agents)
      assert validated[:agents] == agents
    end
  end

  describe "Jason.Encoder" do
    test "encodes agent with all fields" do
      agent =
        Agent.new(
          name: "reviewer",
          description: "Reviews code",
          prompt: "Review.",
          model: "haiku",
          tools: ["View"]
        )

      assert Jason.encode!(agent) ==
               ~s({"description":"Reviews code","model":"haiku","name":"reviewer","prompt":"Review.","tools":["View"]})
    end

    test "omits nil fields" do
      agent = Agent.new(name: "minimal")

      assert Jason.encode!(agent) == ~s({"name":"minimal"})
    end
  end

  describe "JSON.Encoder" do
    test "encodes agent with all fields" do
      agent =
        Agent.new(
          name: "reviewer",
          description: "Reviews code",
          prompt: "Review.",
          model: "haiku",
          tools: ["View"]
        )

      assert JSON.encode!(agent) ==
               ~s({"description":"Reviews code","model":"haiku","name":"reviewer","prompt":"Review.","tools":["View"]})
    end

    test "omits nil fields" do
      agent = Agent.new(name: "minimal")

      assert JSON.encode!(agent) == ~s({"name":"minimal"})
    end
  end
end
