defmodule Joq.Timing do
  @moduledoc """
  Provides timing functions for internal use
  """

  @doc "Returns a monotonic timestamp in milliseconds"
  @spec now :: integer
  def now, do: System.monotonic_time(:milli_seconds)
end