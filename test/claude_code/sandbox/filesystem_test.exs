defmodule ClaudeCode.Sandbox.FilesystemTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Sandbox.Filesystem

  describe "new/1" do
    test "creates filesystem with all fields from keyword list" do
      fs =
        Filesystem.new(
          allow_write: ["/tmp/build", "~/.kube"],
          deny_write: ["/etc"],
          deny_read: ["~/.aws/credentials"]
        )

      assert %Filesystem{
               allow_write: ["/tmp/build", "~/.kube"],
               deny_write: ["/etc"],
               deny_read: ["~/.aws/credentials"]
             } = fs
    end

    test "creates filesystem with no fields" do
      fs = Filesystem.new([])
      assert %Filesystem{allow_write: nil, deny_write: nil, deny_read: nil} = fs
    end

    test "creates filesystem from atom-keyed map" do
      fs = Filesystem.new(%{allow_write: ["/tmp"], deny_read: ["~/.ssh"]})
      assert fs.allow_write == ["/tmp"]
      assert fs.deny_read == ["~/.ssh"]
      assert fs.deny_write == nil
    end

    test "creates filesystem from string-keyed map" do
      fs = Filesystem.new(%{"allow_write" => ["/tmp"], "deny_read" => ["~/.ssh"]})
      assert fs.allow_write == ["/tmp"]
      assert fs.deny_read == ["~/.ssh"]
    end

    test "creates filesystem from camelCase string-keyed map" do
      fs = Filesystem.new(%{"allowWrite" => ["/tmp"], "denyRead" => ["~/.ssh"]})
      assert fs.allow_write == ["/tmp"]
      assert fs.deny_read == ["~/.ssh"]
    end

    test "ignores unknown keys" do
      fs = Filesystem.new(allow_write: ["/tmp"], bogus: true)
      assert fs.allow_write == ["/tmp"]
    end
  end

  describe "to_settings_map/1" do
    test "converts to camelCase map" do
      fs =
        Filesystem.new(
          allow_write: ["/tmp/build"],
          deny_write: ["/etc"],
          deny_read: ["~/.aws"]
        )

      assert Filesystem.to_settings_map(fs) == %{
               "allowWrite" => ["/tmp/build"],
               "denyWrite" => ["/etc"],
               "denyRead" => ["~/.aws"]
             }
    end

    test "omits nil fields" do
      fs = Filesystem.new(allow_write: ["/tmp"])

      assert Filesystem.to_settings_map(fs) == %{
               "allowWrite" => ["/tmp"]
             }
    end

    test "returns empty map when all fields nil" do
      fs = Filesystem.new([])
      assert Filesystem.to_settings_map(fs) == %{}
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON" do
      fs = Filesystem.new(allow_write: ["/tmp"], deny_read: ["~/.aws"])
      decoded = fs |> Jason.encode!() |> Jason.decode!()
      assert decoded == %{"allowWrite" => ["/tmp"], "denyRead" => ["~/.aws"]}
    end
  end

  describe "JSON.Encoder" do
    test "encodes to JSON" do
      fs = Filesystem.new(allow_write: ["/tmp"], deny_read: ["~/.aws"])
      decoded = fs |> JSON.encode!() |> JSON.decode!()
      assert decoded == %{"allowWrite" => ["/tmp"], "denyRead" => ["~/.aws"]}
    end
  end
end
