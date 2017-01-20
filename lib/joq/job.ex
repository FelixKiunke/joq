defmodule Joq.Job do
  defstruct [:id, :worker, :args, :retry, :delay_until]

  alias Joq.Retry
  import Joq.Timing

  def make(id, worker, args, options \\ []) do
    # Throw errors for invalid configs
    Retry.make_config(options[:retry])

    delay_until = options[:delay_for] && now + options[:delay_for]

    %__MODULE__{id: id, worker: worker, args: args, retry: options[:retry],
                delay_until: delay_until}
  end

  @doc """
  Returns true for jobs that have the same worker and arguments
  """
  def is_equal(a, b) do
    a.worker == b.worker and a.args == b.args
  end
end
