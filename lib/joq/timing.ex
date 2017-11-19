defmodule Joq.Timing do
  @moduledoc """
  Provides timing functions for internal use. Timestamps used by Joq are always
  in Erlang's monotonic time. See the 'Time' section in the `System` docs.
  """

  @doc "Returns a monotonic timestamp in milliseconds"
  @spec now :: integer
  def now, do: System.monotonic_time(:milli_seconds)
end