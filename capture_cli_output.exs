#!/usr/bin/env elixir

# Script to capture Claude CLI JSON output for different scenarios
# This helps us understand the actual message structure for Phase 2 implementation

defmodule CLICapture do
  @test_cases [
    # Simple text response
    %{
      name: "simple_hello",
      query: "Say hello",
      description: "Simple text response without tools",
      extra_args: "--dangerously-skip-permissions"
    },
    
    # Math calculation
    %{
      name: "math_calculation",
      query: "What is 2 + 2?",
      description: "Basic math response",
      extra_args: "--dangerously-skip-permissions"
    },
    
    # File listing with tools
    %{
      name: "file_listing",
      query: "What files are in the current directory?",
      description: "Should trigger LS tool",
      extra_args: "--dangerously-skip-permissions"
    },
    
    # File creation with tools
    %{
      name: "create_file",
      query: "Create a file named test.txt with the content 'Hello from Claude'",
      description: "Should trigger write tool",
      extra_args: "--dangerously-skip-permissions"
    },
    
    # File read with tools
    %{
      name: "read_file",
      query: "Read the README.md file and summarize what this project does",
      description: "Should trigger read tool then analysis",
      extra_args: "--dangerously-skip-permissions"
    },
    
    # Error case with tools
    %{
      name: "error_case",
      query: "Read a file that does not exist: /nonexistent/file.txt",
      description: "Should show error handling",
      extra_args: "--dangerously-skip-permissions"
    },
    
    # Permission denial cases
    %{
      name: "create_file_denied",
      query: "Create a file named denied.txt with content 'This should be denied'",
      description: "Should be denied without permissions"
    },
    
    %{
      name: "read_file_default",
      query: "Read the README.md file",
      description: "Test default permission mode for reads"
    },
    
    # Permission tests
    %{
      name: "permission_skip",
      query: "Create a file named skip_test.txt with content 'Permissions skipped'",
      description: "With skipped permissions (dangerous mode)",
      extra_args: "--dangerously-skip-permissions"
    },
    
    %{
      name: "allowed_tools_read",
      query: "Read the README.md file then try to create a file",
      description: "With only Read tool allowed",
      extra_args: "--allowedTools Read"
    },
    
    %{
      name: "disallowed_write",
      query: "Create a file named blocked.txt",
      description: "With Write tool disallowed",
      extra_args: "--disallowedTools Write"
    },
    
    # Complex tool chain
    %{
      name: "complex_tool_chain",
      query: "Read the mix.exs file, extract the version number, and create a VERSION.txt file with that version",
      description: "Multiple tools in sequence",
      extra_args: "--dangerously-skip-permissions"
    }
  ]
  
  def run do
    # Ensure we have fixtures directory
    File.mkdir_p!("test/fixtures/cli_messages")
    
    # Check if claude CLI exists
    claude_path = find_claude_cli()
    
    if claude_path do
      IO.puts("Found claude CLI at: #{claude_path}")
      IO.puts("Starting capture of CLI outputs...\n")
      
      Enum.each(@test_cases, &capture_test_case(&1, claude_path))
      
      IO.puts("\n✅ All test cases captured!")
      IO.puts("Check test/fixtures/cli_messages/ for the JSON files")
    else
      IO.puts("❌ Claude CLI not found!")
      IO.puts("Please ensure 'claude' is installed and in your PATH")
      IO.puts("\nYou can install it with:")
      IO.puts("  npm install -g @anthropic-ai/claude-cli")
    end
  end
  
  defp find_claude_cli do
    case System.cmd("which", ["claude"], stderr_to_stdout: true) do
      {path, 0} -> String.trim(path)
      _ -> nil
    end
  end
  
  defp capture_test_case(test_case, claude_path) do
    IO.puts("\n📝 Capturing: #{test_case.name}")
    IO.puts("   Query: #{test_case.query}")
    IO.puts("   Description: #{test_case.description}")
    
    # Build the command with proper escaping
    # Using echo to provide input and prevent hanging
    extra_args = Map.get(test_case, :extra_args, "")
    
    cmd = """
    echo '#{escape_quotes(test_case.query)}' | \
    #{claude_path} \
      --output-format stream-json \
      --verbose \
      --print \
      #{extra_args} \
      2>&1
    """
    
    # Run the command
    case System.cmd("sh", ["-c", cmd], env: [{"ANTHROPIC_API_KEY", api_key()}]) do
      {output, 0} ->
        # Save the output
        output_file = "test/fixtures/cli_messages/#{test_case.name}.json"
        
        # Split by newlines and parse each JSON message
        messages = output
          |> String.split("\n")
          |> Enum.filter(&(&1 != ""))
          |> Enum.map(&parse_and_format_json/1)
          |> Enum.join("\n")
        
        File.write!(output_file, messages)
        IO.puts("   ✓ Saved to: #{output_file}")
        
      {output, code} ->
        IO.puts("   ❌ Failed with exit code: #{code}")
        IO.puts("   Output: #{output}")
    end
  end
  
  defp escape_quotes(str) do
    String.replace(str, "'", "'\"'\"'")
  end
  
  defp parse_and_format_json(line) do
    case Jason.decode(line) do
      {:ok, json} -> Jason.encode!(json, pretty: true)
      {:error, _} -> line
    end
  rescue
    _ -> line
  end
  
  defp api_key do
    System.get_env("ANTHROPIC_API_KEY") || 
      raise "Please set ANTHROPIC_API_KEY environment variable"
  end
end

# Also create a simple test runner that doesn't require API key
defmodule MockCLICapture do
  @mock_responses %{
    "simple_hello" => [
      %{
        "type" => "system",
        "content" => "Initializing Claude CLI...",
        "timestamp" => "2024-01-01T00:00:00Z"
      },
      %{
        "type" => "assistant",
        "content" => [
          %{"type" => "text", "text" => "Hello! How can I assist you today?"}
        ],
        "timestamp" => "2024-01-01T00:00:01Z"
      },
      %{
        "type" => "result",
        "result" => "Hello! How can I assist you today?",
        "timestamp" => "2024-01-01T00:00:02Z"
      }
    ],
    
    "tool_use_example" => [
      %{
        "type" => "system",
        "content" => "Initializing Claude CLI...",
        "timestamp" => "2024-01-01T00:00:00Z"
      },
      %{
        "type" => "assistant", 
        "content" => [
          %{"type" => "text", "text" => "I'll create that file for you."},
          %{
            "type" => "tool_use",
            "id" => "tool_123",
            "name" => "write_file",
            "input" => %{
              "path" => "test.txt",
              "content" => "Hello from Claude"
            }
          }
        ],
        "timestamp" => "2024-01-01T00:00:01Z"
      },
      %{
        "type" => "tool_result",
        "tool_use_id" => "tool_123",
        "content" => "File created successfully",
        "timestamp" => "2024-01-01T00:00:02Z"
      },
      %{
        "type" => "result",
        "result" => "I've created the file test.txt with the content 'Hello from Claude'.",
        "timestamp" => "2024-01-01T00:00:03Z"
      }
    ]
  }
  
  def create_mock_fixtures do
    File.mkdir_p!("test/fixtures/cli_messages")
    
    Enum.each(@mock_responses, fn {name, messages} ->
      output_file = "test/fixtures/cli_messages/mock_#{name}.json"
      
      content = messages
        |> Enum.map(&Jason.encode!(&1, pretty: true))
        |> Enum.join("\n")
      
      File.write!(output_file, content)
      IO.puts("Created mock fixture: #{output_file}")
    end)
  end
end

# Main execution
case System.argv() do
  ["--mock"] ->
    IO.puts("Creating mock fixtures (no API key required)...")
    MockCLICapture.create_mock_fixtures()
    
  _ ->
    IO.puts("Capturing real CLI output (requires ANTHROPIC_API_KEY)...")
    IO.puts("Use --mock flag to create mock fixtures instead\n")
    CLICapture.run()
end