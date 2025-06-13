defmodule ClaudeCodeTest do
  use ExUnit.Case

  doctest ClaudeCode

  test "greets the world" do
    assert ClaudeCode.hello() == :world
  end
end
