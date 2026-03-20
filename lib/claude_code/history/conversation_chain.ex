# Builds conversation chains from JSONL transcript entries using `parentUuid` links.
#
# Ports the Python SDK's `_build_conversation_chain` algorithm:
# 1. Index all entries by `uuid`
# 2. Find leaf nodes (entries whose uuid appears in no other entry's parentUuid)
# 3. Among leaves, prefer main chain (not sidechain/team/meta), pick highest file position
# 4. Walk from leaf to root via `parentUuid`
# 5. Reverse for chronological order
# 6. Filter to visible messages (user/assistant, not meta/sidechain/team)
defmodule ClaudeCode.History.ConversationChain do
  @moduledoc false

  alias ClaudeCode.History.SessionMessage

  # Transcript entry types that carry uuid + parentUuid chain links.
  @transcript_entry_types ["user", "assistant", "progress", "system", "attachment"]

  @doc """
  Parses JSONL content into transcript entries.

  Only keeps entries that have a uuid and are transcript message types.
  """
  @spec parse_entries(String.t()) :: [map()]
  def parse_entries(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(String.trim(line)) do
        {:ok, %{"type" => type, "uuid" => uuid} = entry}
        when is_binary(uuid) ->
          if type in @transcript_entry_types, do: [entry], else: []

        _ ->
          []
      end
    end)
  end

  @doc """
  Builds the conversation chain by finding the leaf and walking `parentUuid`.

  Returns entries in chronological order (root -> leaf).

  `logicalParentUuid` (set on compact_boundary entries) is intentionally
  NOT followed, matching VS Code IDE behavior.
  """
  @spec build(list(map())) :: list(map())
  def build([]), do: []

  def build(entries) do
    # Index by uuid for O(1) parent lookup
    by_uuid = Map.new(entries, fn entry -> {entry["uuid"], entry} end)

    # Build index of entry positions for tie-breaking
    entry_index =
      entries
      |> Enum.with_index()
      |> Map.new(fn {entry, idx} -> {entry["uuid"], idx} end)

    # Find terminal entries (no children point to them via parentUuid)
    parent_uuids =
      entries
      |> Enum.flat_map(fn entry ->
        case entry["parentUuid"] do
          parent when is_binary(parent) -> [parent]
          _ -> []
        end
      end)
      |> MapSet.new()

    terminals = Enum.filter(entries, fn e -> e["uuid"] not in parent_uuids end)

    # From each terminal, walk back to find the nearest user/assistant leaf
    leaves = find_leaves(terminals, by_uuid)

    case leaves do
      [] ->
        []

      _ ->
        # Pick the leaf from the main chain (not sidechain/team/meta)
        leaf = pick_best_leaf(leaves, entry_index)

        # Walk from leaf to root via parentUuid
        # walk_to_root prepends entries, so result is already root→leaf (chronological)
        walk_to_root(leaf, by_uuid)
    end
  end

  @doc """
  Filters entries to only visible user/assistant messages.
  """
  @spec filter_visible(list(map())) :: list(map())
  def filter_visible(entries) do
    Enum.filter(entries, &visible_message?/1)
  end

  @doc """
  Converts a transcript entry to a `SessionMessage` struct with parsed content.
  """
  @spec to_session_message(map()) :: SessionMessage.t()
  def to_session_message(entry) do
    SessionMessage.from_entry(entry)
  end

  # -- Private ----------------------------------------------------------------

  defp find_leaves(terminals, by_uuid) do
    Enum.flat_map(terminals, fn terminal ->
      case walk_to_user_assistant(terminal, by_uuid, MapSet.new()) do
        nil -> []
        leaf -> [leaf]
      end
    end)
  end

  defp walk_to_user_assistant(nil, _by_uuid, _seen), do: nil

  defp walk_to_user_assistant(entry, by_uuid, seen) do
    uuid = entry["uuid"]

    if uuid in seen do
      nil
    else
      seen = MapSet.put(seen, uuid)

      if entry["type"] in ["user", "assistant"] do
        entry
      else
        parent_uuid = entry["parentUuid"]

        if is_binary(parent_uuid) do
          walk_to_user_assistant(Map.get(by_uuid, parent_uuid), by_uuid, seen)
        end
      end
    end
  end

  defp pick_best_leaf(leaves, entry_index) do
    main_leaves =
      Enum.filter(leaves, fn leaf ->
        not (leaf["isSidechain"] == true) and
          is_nil(leaf["teamName"]) and
          not (leaf["isMeta"] == true)
      end)

    candidates = if main_leaves == [], do: leaves, else: main_leaves

    Enum.max_by(candidates, fn leaf ->
      Map.get(entry_index, leaf["uuid"], -1)
    end)
  end

  defp walk_to_root(leaf, by_uuid) do
    do_walk_to_root(leaf, by_uuid, MapSet.new(), [])
  end

  defp do_walk_to_root(nil, _by_uuid, _seen, chain), do: chain

  defp do_walk_to_root(entry, by_uuid, seen, chain) do
    uuid = entry["uuid"]

    if uuid in seen do
      chain
    else
      seen = MapSet.put(seen, uuid)
      chain = [entry | chain]

      parent_uuid = entry["parentUuid"]

      if is_binary(parent_uuid) do
        do_walk_to_root(Map.get(by_uuid, parent_uuid), by_uuid, seen, chain)
      else
        chain
      end
    end
  end

  defp visible_message?(entry) do
    entry["type"] in ["user", "assistant"] and
      not (entry["isMeta"] == true) and
      not (entry["isSidechain"] == true) and
      is_nil(entry["teamName"])
  end
end
