defmodule ClaudeCode.Session.AccountInfoTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Session.AccountInfo

  describe "new/1" do
    test "parses all fields from JSON" do
      info =
        AccountInfo.new(%{
          "email" => "user@example.com",
          "organization" => "Acme Corp",
          "subscription_type" => "pro",
          "token_source" => "oauth",
          "api_key_source" => "user"
        })

      assert info.email == "user@example.com"
      assert info.organization == "Acme Corp"
      assert info.subscription_type == "pro"
      assert info.token_source == "oauth"
      assert info.api_key_source == "user"
    end

    test "handles missing optional fields" do
      info = AccountInfo.new(%{"email" => "user@example.com"})

      assert info.email == "user@example.com"
      assert info.organization == nil
      assert info.subscription_type == nil
      assert info.token_source == nil
      assert info.api_key_source == nil
    end

    test "handles empty map" do
      info = AccountInfo.new(%{})

      assert info.email == nil
      assert info.organization == nil
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON with snake_case keys" do
      info =
        AccountInfo.new(%{
          "email" => "user@example.com",
          "subscription_type" => "pro"
        })

      decoded = info |> Jason.encode!() |> Jason.decode!()

      assert decoded == %{
               "email" => "user@example.com",
               "subscription_type" => "pro"
             }
    end
  end
end
