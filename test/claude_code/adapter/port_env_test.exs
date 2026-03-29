defmodule ClaudeCode.Adapter.PortEnvTest do
  use ExUnit.Case, async: false

  alias ClaudeCode.Adapter.Port

  describe "build_env/2 with inherit_env" do
    test "with inherit_env: :all strips CLAUDECODE" do
      System.put_env("CLAUDECODE", "1")
      System.put_env("CLAUDE_CODE_TEST_INHERIT", "yes")

      try do
        env = Port.build_env([inherit_env: :all], nil)

        refute Map.has_key?(env, "CLAUDECODE")
        assert env["CLAUDE_CODE_TEST_INHERIT"] == "yes"
        assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      after
        System.delete_env("CLAUDECODE")
        System.delete_env("CLAUDE_CODE_TEST_INHERIT")
      end
    end

    test "with inherit_env: [] only has SDK vars and user env" do
      System.put_env("CLAUDE_CODE_TEST_BLOCKED", "should_not_appear")

      try do
        env = Port.build_env([inherit_env: [], env: %{"MY_VAR" => "hello"}], nil)

        refute Map.has_key?(env, "CLAUDE_CODE_TEST_BLOCKED")
        refute Map.has_key?(env, "PATH")
        assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
        assert env["CLAUDE_AGENT_SDK_VERSION"] == ClaudeCode.version()
        assert env["MY_VAR"] == "hello"
      after
        System.delete_env("CLAUDE_CODE_TEST_BLOCKED")
      end
    end

    test "with inherit_env list only inherits matching vars" do
      System.put_env("CLAUDE_CODE_TEST_ALLOWED", "yes")
      System.put_env("CLAUDE_CODE_TEST_BLOCKED", "no")

      try do
        env = Port.build_env([inherit_env: ["CLAUDE_CODE_TEST_ALLOWED"]], nil)

        assert env["CLAUDE_CODE_TEST_ALLOWED"] == "yes"
        refute Map.has_key?(env, "CLAUDE_CODE_TEST_BLOCKED")
        assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      after
        System.delete_env("CLAUDE_CODE_TEST_ALLOWED")
        System.delete_env("CLAUDE_CODE_TEST_BLOCKED")
      end
    end

    test "with inherit_env prefix tuples" do
      System.put_env("HTTP_PROXY", "http://proxy")
      System.put_env("HTTPS_PROXY", "https://proxy")
      System.put_env("SECRET_KEY", "should_not_appear")

      try do
        env = Port.build_env([inherit_env: [{:prefix, "HTTP"}]], nil)

        assert env["HTTP_PROXY"] == "http://proxy"
        assert env["HTTPS_PROXY"] == "https://proxy"
        refute Map.has_key?(env, "SECRET_KEY")
      after
        System.delete_env("HTTP_PROXY")
        System.delete_env("HTTPS_PROXY")
        System.delete_env("SECRET_KEY")
      end
    end

    test "default (no inherit_env) inherits all except CLAUDECODE" do
      System.put_env("CLAUDECODE", "1")
      System.put_env("CLAUDE_CODE_TEST_DEFAULT", "yes")

      try do
        env = Port.build_env([], nil)

        refute Map.has_key?(env, "CLAUDECODE")
        assert env["CLAUDE_CODE_TEST_DEFAULT"] == "yes"
      after
        System.delete_env("CLAUDECODE")
        System.delete_env("CLAUDE_CODE_TEST_DEFAULT")
      end
    end
  end
end
