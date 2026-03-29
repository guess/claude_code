defmodule ClaudeCode.Adapter.PortEnvTest do
  use ExUnit.Case, async: false

  alias ClaudeCode.Adapter.Port

  @test_vars %{
    "CLAUDECODE" => "1",
    "CLAUDE_CODE_TEST_INHERIT" => "yes",
    "CLAUDE_CODE_TEST_BLOCKED" => "no",
    "CLAUDE_CODE_TEST_ALLOWED" => "yes",
    "CLAUDE_CODE_TEST_DEFAULT" => "yes",
    "HTTP_PROXY" => "http://proxy",
    "HTTPS_PROXY" => "https://proxy",
    "SECRET_KEY" => "secret"
  }

  describe "build_env/2 with inherit_env" do
    setup do
      Enum.each(@test_vars, fn {key, value} -> System.put_env(key, value) end)

      on_exit(fn ->
        Enum.each(@test_vars, fn {key, _} -> System.delete_env(key) end)
      end)
    end

    test ":all strips CLAUDECODE but keeps other vars and SDK vars" do
      env = Port.build_env([inherit_env: :all], nil)

      refute Map.has_key?(env, "CLAUDECODE")
      assert env["CLAUDE_CODE_TEST_INHERIT"] == "yes"
      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
    end

    test "[] only has SDK vars and user env" do
      env = Port.build_env([inherit_env: [], env: %{"MY_VAR" => "hello"}], nil)

      refute Map.has_key?(env, "CLAUDE_CODE_TEST_BLOCKED")
      refute Map.has_key?(env, "PATH")
      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      assert env["CLAUDE_AGENT_SDK_VERSION"] == ClaudeCode.version()
      assert env["MY_VAR"] == "hello"
    end

    test "explicit list only inherits matching vars" do
      env = Port.build_env([inherit_env: ["CLAUDE_CODE_TEST_ALLOWED"]], nil)

      assert env["CLAUDE_CODE_TEST_ALLOWED"] == "yes"
      refute Map.has_key?(env, "CLAUDE_CODE_TEST_BLOCKED")
      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
    end

    test "prefix tuples match by prefix" do
      env = Port.build_env([inherit_env: [{:prefix, "HTTP"}]], nil)

      assert env["HTTP_PROXY"] == "http://proxy"
      assert env["HTTPS_PROXY"] == "https://proxy"
      refute Map.has_key?(env, "SECRET_KEY")
    end

    test "default inherits all except CLAUDECODE" do
      env = Port.build_env([], nil)

      refute Map.has_key?(env, "CLAUDECODE")
      assert env["CLAUDE_CODE_TEST_DEFAULT"] == "yes"
    end
  end
end
