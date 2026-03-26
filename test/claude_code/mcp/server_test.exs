defmodule ClaudeCode.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Anubis.MCP.Error
  alias Anubis.Server.Component
  alias Anubis.Server.Frame
  alias Anubis.Server.Response
  alias ClaudeCode.MCP.Server
  alias ClaudeCode.TestTools.Add
  alias ClaudeCode.TestTools.FailingTool
  alias ClaudeCode.TestTools.GetTime
  alias ClaudeCode.TestTools.Greet
  alias ClaudeCode.TestTools.ReturnMap

  describe "__tool_server__/0" do
    test "returns server metadata with name and tool modules" do
      info = ClaudeCode.TestTools.__tool_server__()

      assert info.name == "test-tools"
      assert is_list(info.tools)
      assert length(info.tools) == 5
    end

    test "tool modules are correctly named" do
      %{tools: tools} = ClaudeCode.TestTools.__tool_server__()
      module_names = tools |> Enum.map(& &1) |> Enum.sort()

      assert Add in module_names
      assert Greet in module_names
      assert GetTime in module_names
      assert ReturnMap in module_names
      assert FailingTool in module_names
    end
  end

  describe "generated tool modules" do
    test "have __tool_name__/0 returning the string name" do
      assert Add.__tool_name__() == "add"
      assert Greet.__tool_name__() == "greet"
      assert GetTime.__tool_name__() == "get_time"
    end

    test "have input_schema/0 returning JSON Schema" do
      schema = Add.input_schema()

      assert schema["type"] == "object"
      assert schema["properties"]["x"]["type"] == "integer"
      assert schema["properties"]["y"]["type"] == "integer"
      assert "x" in schema["required"]
      assert "y" in schema["required"]
    end

    test "tool with no fields has empty object schema" do
      schema = GetTime.input_schema()
      assert schema["type"] == "object"
    end

    test "have description from @moduledoc" do
      assert Component.get_description(Add) == "Add two numbers"
      assert Component.get_description(Greet) == "Greet a user"
    end

    test "are Anubis Components" do
      assert Component.component?(Add)
      assert Component.get_type(Add) == :tool
    end
  end

  describe "execute/2" do
    test "returns {:reply, Response, Frame} for text results" do
      frame = Frame.new()
      assert {:reply, %Response{} = resp, ^frame} = Add.execute(%{x: 3, y: 4}, frame)
      assert Response.to_protocol(resp) == %{"content" => [%{"type" => "text", "text" => "7"}], "isError" => false}
    end

    test "returns {:reply, Response, Frame} for map results" do
      frame = Frame.new()
      assert {:reply, %Response{} = resp, ^frame} = ReturnMap.execute(%{key: "test"}, frame)
      protocol = Response.to_protocol(resp)
      assert protocol["isError"] == false
      [%{"text" => json}] = protocol["content"]
      assert Jason.decode!(json) == %{"key" => "test", "value" => "data"}
    end

    test "returns {:reply, Response, Frame} with isError for failing tools" do
      frame = Frame.new()
      assert {:reply, %Response{} = resp, ^frame} = FailingTool.execute(%{}, frame)
      assert Response.to_protocol(resp)["isError"] == true
    end

    test "execute/1 tools ignore frame" do
      frame = Frame.new()
      assert {:reply, %Response{} = resp, ^frame} = GetTime.execute(%{}, frame)
      protocol = Response.to_protocol(resp)
      [%{"text" => time_str}] = protocol["content"]
      assert {:ok, _, _} = DateTime.from_iso8601(time_str)
    end
  end

  describe "execute/2 with frame" do
    defmodule FrameTools do
      @moduledoc false
      use Server, name: "frame-test"

      tool :whoami do
        description "Returns user from frame assigns"

        def execute(_params, frame) do
          case frame.assigns do
            %{user: user} -> {:ok, "User: #{user}"}
            _ -> {:error, "No user"}
          end
        end
      end
    end

    test "passes frame to arity-2 execute" do
      frame = Frame.new(%{user: "alice"})
      assert {:reply, %Response{} = resp, ^frame} = FrameTools.Whoami.execute(%{}, frame)
      protocol = Response.to_protocol(resp)
      assert protocol["content"] == [%{"type" => "text", "text" => "User: alice"}]
    end

    test "empty assigns when not provided" do
      frame = Frame.new()
      assert {:reply, %Response{} = resp, ^frame} = FrameTools.Whoami.execute(%{}, frame)
      assert Response.to_protocol(resp)["isError"] == true
    end
  end

  describe "execute return value variants" do
    defmodule ReturnVariantTools do
      @moduledoc false
      use Server, name: "return-variants"

      tool :ok_with_frame do
        description "Returns ok with updated frame"

        def execute(_params, frame) do
          {:ok, "updated", Frame.assign(frame, :touched, true)}
        end
      end

      tool :error_with_frame do
        description "Returns error with updated frame"

        def execute(_params, frame) do
          {:error, "failed", Frame.assign(frame, :failed, true)}
        end
      end

      tool :noreply do
        description "Returns noreply with updated frame"

        def execute(_params, frame) do
          {:noreply, Frame.assign(frame, :silent, true)}
        end
      end

      tool :native_reply do
        description "Returns native Anubis response"

        def execute(_params, frame) do
          {:reply, Response.text(Response.tool(), "native"), frame}
        end
      end

      tool :native_error do
        description "Returns native Anubis error"

        def execute(_params, frame) do
          {:error, Error.execution("native error"), frame}
        end
      end
    end

    test "{:ok, value, frame} returns response with updated frame" do
      frame = Frame.new()
      assert {:reply, %Response{} = resp, updated_frame} = ReturnVariantTools.OkWithFrame.execute(%{}, frame)
      assert Response.to_protocol(resp)["content"] == [%{"type" => "text", "text" => "updated"}]
      assert updated_frame.assigns[:touched] == true
    end

    test "{:error, msg, frame} returns error response with updated frame" do
      frame = Frame.new()
      assert {:reply, %Response{} = resp, updated_frame} = ReturnVariantTools.ErrorWithFrame.execute(%{}, frame)
      assert Response.to_protocol(resp)["isError"] == true
      assert updated_frame.assigns[:failed] == true
    end

    test "{:noreply, frame} passes through" do
      frame = Frame.new()
      assert {:noreply, updated_frame} = ReturnVariantTools.Noreply.execute(%{}, frame)
      assert updated_frame.assigns[:silent] == true
    end

    test "{:reply, Response, frame} passes through native Anubis" do
      frame = Frame.new()
      assert {:reply, %Response{} = resp, ^frame} = ReturnVariantTools.NativeReply.execute(%{}, frame)
      assert Response.to_protocol(resp)["content"] == [%{"type" => "text", "text" => "native"}]
    end

    test "{:error, Error, frame} passes through native Anubis error" do
      frame = Frame.new()
      assert {:error, %Error{} = error, ^frame} = ReturnVariantTools.NativeError.execute(%{}, frame)
      assert error.message == "native error"
    end
  end

  describe "sdk_server?/1" do
    test "returns true for MCP.Server modules" do
      assert Server.sdk_server?(ClaudeCode.TestTools)
    end

    test "returns false for regular modules" do
      refute Server.sdk_server?(String)
    end

    test "returns false for non-existent modules" do
      refute Server.sdk_server?(DoesNotExist)
    end
  end
end
