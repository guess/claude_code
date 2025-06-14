defmodule ClaudeCode.Message do
  @moduledoc """
  Utilities for working with messages from the Claude CLI.
  
  Messages can be system initialization, assistant responses, user tool results,
  or final result messages. This module provides functions to parse and work with
  any message type.
  """
  
  alias ClaudeCode.Message.{System, Assistant, User, Result}
  
  @type t :: System.t() | Assistant.t() | User.t() | Result.t()
  
  @doc """
  Parses a message from JSON data based on its type.
  
  ## Examples
  
      iex> Message.parse(%{"type" => "system", ...})
      {:ok, %System{...}}
      
      iex> Message.parse(%{"type" => "unknown"})
      {:error, {:unknown_message_type, "unknown"}}
  """
  @spec parse(map()) :: {:ok, t()} | {:error, term()}
  def parse(%{"type" => type} = data) do
    case type do
      "system" -> System.new(data)
      "assistant" -> Assistant.new(data)
      "user" -> User.new(data)
      "result" -> Result.new(data)
      other -> {:error, {:unknown_message_type, other}}
    end
  end
  
  def parse(_), do: {:error, :missing_type}
  
  @doc """
  Parses a list of messages.
  
  Returns {:ok, messages} if all messages parse successfully,
  or {:error, {:parse_error, index, error}} for the first failure.
  """
  @spec parse_all(list(map())) :: {:ok, [t()]} | {:error, term()}
  def parse_all(messages) when is_list(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {message, index}, {:ok, acc} ->
      case parse(message) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, error} -> {:halt, {:error, {:parse_error, index, error}}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end
  
  @doc """
  Parses a newline-delimited JSON stream from the CLI.
  
  This is the format output by the CLI with --output-format stream-json.
  """
  @spec parse_stream(String.t()) :: {:ok, [t()]} | {:error, term()}
  def parse_stream(stream) when is_binary(stream) do
    stream
    |> String.split("\n", trim: true)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {line, index}, {:ok, acc} ->
      case Jason.decode(line) do
        {:ok, json} ->
          case parse(json) do
            {:ok, message} -> {:cont, {:ok, [message | acc]}}
            {:error, error} -> {:halt, {:error, {:parse_error, index, error}}}
          end
        {:error, error} ->
          {:halt, {:error, {:json_decode_error, index, error}}}
      end
    end)
    |> case do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      error -> error
    end
  end
  
  @doc """
  Checks if a value is any type of message.
  """
  @spec is_message?(any()) :: boolean()
  def is_message?(%System{}), do: true
  def is_message?(%Assistant{}), do: true
  def is_message?(%User{}), do: true
  def is_message?(%Result{}), do: true
  def is_message?(_), do: false
  
  @doc """
  Returns the type of a message.
  """
  @spec message_type(t()) :: :system | :assistant | :user | :result
  def message_type(%System{type: type}), do: type
  def message_type(%Assistant{type: type}), do: type
  def message_type(%User{type: type}), do: type
  def message_type(%Result{type: type}), do: type
end