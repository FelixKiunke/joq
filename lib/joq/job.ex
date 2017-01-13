defmodule Joq.Job do
  defstruct [:id, :worker, :args, :retry]

  alias Joq.Retry

  def make(id, worker, args, options \\ []) do
    # Throw errors for invalid configs
    Retry.make_config(options[:retry])

    %__MODULE__{id: id, worker: worker, args: args, retry: options[:retry]}
  end
end
