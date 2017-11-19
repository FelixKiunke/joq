defmodule Joq.Job do
  @moduledoc """
  Internal representation of a job instance.

  See [below](#t:t/0) for the format of Job structs.
  """

  import Joq.Timing

  alias Joq.Retry

  defstruct [:id, :worker, :args, :retry, :delay_until]

  @typedoc """
  The type of a Job struct.

  Job structs contain the following fields:

    * `:id` - an identifier string that is unique for each job
    * `:worker` - the worker module (see `Joq.Worker` for more info)
    * `:args` - the arguments the worker function will be called with
    * `:retry` - an optional retry configuration (see `Joq.Retry` for more info)
    * `:delay_until` - an optional timestamp when the job should be run. This is
      an Erlang monotonic timestamp (see `Joq.Timing`)
  """
  @type t :: %__MODULE__{
    id: String.t,
    worker: atom,
    args: term,
    retry: Retry.t | nil,
    delay_until: integer | nil
  }

  @doc """
  Create a job. Used internally in `Joq.enqueue/3`.

  Valid options are `retry` and `delay_for`. See `Joq.Retry` for retry configs.
  `delay_for` is the amount of milliseconds to wait before executing the job.

  ## Examples
      # Create a job with an id of "foo" that will be run as
      # MyWorker.perform(param: 1) and will not be retried on errors
      Job.make("foo", MyWorker, [param: 1], retry: :no_retry)

      # Create a job that will be run as MyWorker.perform(:param) in 3 seconds
      Job.make("foo", MyWorker, :param, delay_for: 3_000)
  """
  @spec make(String.t, atom, term, keyword) :: t
  def make(id, worker, args, options \\ []) do
    # Throw errors for invalid configs
    Retry.make_config(options[:retry])

    delay_until = options[:delay_for] && now() + options[:delay_for]

    %__MODULE__{id: id, worker: worker, args: args, retry: options[:retry],
                delay_until: delay_until}
  end

  @doc """
  Returns true for jobs that have the same worker and arguments.

  These jobs are considered duplicates and will be ignored if
  `duplicates: :drop` is set (see `Joq.Worker` for more info)
  """
  @spec is_equal(t, t) :: boolean
  def is_equal(a, b) do
    a.worker == b.worker and a.args == b.args
  end
end
