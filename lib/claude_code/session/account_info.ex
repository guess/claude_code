defmodule ClaudeCode.Session.AccountInfo do
  @moduledoc """
  Information about the authenticated user's account.

  Returned as part of the initialization response from the CLI.

  ## Fields

    * `:email` - Account email address
    * `:organization` - Organization name
    * `:subscription_type` - Subscription type (e.g., "pro", "team")
    * `:token_source` - Source of the authentication token
    * `:api_key_source` - Source of the API key (e.g., "user", "project", "org")
  """

  use ClaudeCode.JSONEncoder

  defstruct [
    :email,
    :organization,
    :subscription_type,
    :token_source,
    :api_key_source
  ]

  @type t :: %__MODULE__{
          email: String.t() | nil,
          organization: String.t() | nil,
          subscription_type: String.t() | nil,
          token_source: String.t() | nil,
          api_key_source: String.t() | nil
        }

  @doc """
  Creates an AccountInfo from a JSON map.

  ## Examples

      iex> ClaudeCode.Session.AccountInfo.new(%{"email" => "user@example.com", "subscriptionType" => "pro"})
      %ClaudeCode.Session.AccountInfo{email: "user@example.com", subscription_type: "pro"}

  """
  @spec new(map()) :: t()
  def new(data) when is_map(data) do
    %__MODULE__{
      email: data["email"],
      organization: data["organization"],
      subscription_type: data["subscription_type"],
      token_source: data["token_source"],
      api_key_source: data["api_key_source"]
    }
  end
end
