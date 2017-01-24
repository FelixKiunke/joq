defmodule TimingTest do
  use ExUnit.Case, async: true

  alias Joq.Timing

  test "Timing.now returns a monotonic timestamp" do
    should_be = System.monotonic_time(:milli_seconds)
    assert_in_delta(Timing.now, should_be, 10)
  end
end