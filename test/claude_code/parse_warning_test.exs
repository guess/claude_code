defmodule ClaudeCode.ParseWarningTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ClaudeCode.ParseWarning

  setup do
    ParseWarning.reset()
    :ok
  end

  test "warning server is supervised and running" do
    pid = Process.whereis(ParseWarning)
    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  @tag capture_log: true
  test "deduplicates the same warning across caller process lifecycles" do
    context = "result subtype"
    value = "future_subtype_#{unique_suffix()}"
    expected = "Unrecognized #{context} from CLI: #{inspect(value)}"

    log =
      capture_log(fn ->
        caller =
          spawn(fn ->
            ParseWarning.once(context, value)
          end)

        ref = Process.monitor(caller)
        assert_receive {:DOWN, ^ref, :process, ^caller, _reason}, 1_000

        ParseWarning.once(context, value)
      end)

    assert occurrences(log, expected) == 1
  end

  @tag capture_log: true
  test "bounds retained dedup entries under high-cardinality input" do
    max_entries = ParseWarning.stats().max_entries

    capture_log(fn ->
      Enum.each(1..(max_entries * 3), fn i ->
        ParseWarning.once("stop_reason", "unknown_#{i}_#{unique_suffix()}")
      end)
    end)

    assert ParseWarning.stats().size <= max_entries
  end

  defp occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end

  defp unique_suffix do
    "#{System.unique_integer([:positive])}_#{System.system_time(:microsecond)}"
  end
end
