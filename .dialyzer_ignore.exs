[
  # Add any dialyzer warnings to ignore here
  # Format: {"path/to/file.ex", :warning_type, line_number}

  # MapSet opaque type warnings — known dialyzer limitation with Elixir's MapSet implementation
  {"lib/claude_code/history.ex", :call_without_opaque},
  {"lib/claude_code/history/conversation_chain.ex", :call_without_opaque},
  {"lib/claude_code/history/conversation_chain.ex", :call_with_opaque},

  # Pattern match coverage false positives
  {"lib/claude_code/history.ex", :pattern_match_cov}
]
