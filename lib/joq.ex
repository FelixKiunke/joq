defmodule Joq do
  use Application

  alias Joq.Job
  alias Joq.JobRunner
  alias Joq.Retry

  @doc """
  Enqueue job to be run in the background
  """
  def enqueue(worker, args \\ [], options \\ []) do
    id = :crypto.hash(:md5, UUID.uuid1) |> Base.encode32 |> String.slice(0, 8)
    Job.make(id, worker, args, options)
    |> JobRunner.register_job
  end

  @doc """
  Enqueue for use in pipelines

  Example:

    params
    |> extract_data
    |> Joq.enqueue_to(SendEmailWorker)
  """
  def enqueue_to(args, worker, options \\ []) do
    enqueue(worker, args, options)
  end

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Throws errors if the retry config is invalid
    Application.get_env(:joq, :retry) |> Retry.make_config

    children = [
      worker(JobRunner, []),
      worker(Joq.JobEvent, []),
      worker(Joq.JobQueue, [])
    ]

    # When one process fails we restart all of them to ensure a valid state.
    # Jobs are lost in that case.
    opts = [
      strategy: :one_for_all,
      name: Joq.Supervisor,
      max_seconds: 15,
      max_restarts: 3
    ]
    Supervisor.start_link(children, opts)
  end
end
