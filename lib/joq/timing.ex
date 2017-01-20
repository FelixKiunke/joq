defmodule Joq.Timing do
  def now, do: System.monotonic_time(:milli_seconds)
end