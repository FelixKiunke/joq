defmodule Joq.JobRunner do
  use GenServer
  require Logger

  alias Joq.JobQueue
  alias Joq.JobEvent
  alias Joq.Retry
  import Joq.Timing

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register_job(job) do
    Logger.debug("Enqueued job #{job.id}: #{inspect job.worker}.perform" <>
                 "(#{inspect job.args})" <> (if job.delay_until, do:
                   " (delayed for #{job.delay_until - now()}ms)", else: ""))
    GenServer.cast(__MODULE__, {:register_job, job})
  end

  def handle_cast({:register_job, job}, state) do
    spawn_link fn ->
      job
      |> JobQueue.run
      |> retry_failed
      |> process_result
    end

    {:noreply, state}
  end

  defp retry_failed(status), do: retry_failed(status, 1)
  defp retry_failed({:success, job}, _attempt), do: {:success, job}
  defp retry_failed({:dropped, job}, _attempt), do: {:dropped, job}
  defp retry_failed({:fail, job, error, stack}, attempt) do
    retry_config =
      Application.get_env(:joq, :retry)
      |> Retry.make_config()
      |> Retry.override(job.worker.retry_config)
      |> Retry.override(job.retry)

    if Retry.retry?(retry_config, attempt) do
      delay = Retry.retry_delay(retry_config, attempt)
      Logger.warn("Job #{job.id} failed, will retry in #{delay}ms")

      job
      |> JobQueue.run(delay)
      |> retry_failed(attempt + 1)
    else
      {:fail, job, error, stack}
    end
  end

  defp process_result({:success, job}) do
    JobEvent.finished(job)
  end

  defp process_result({:dropped, job}) do
    Logger.debug("Job #{job.id} dropped as a duplicate")
    JobEvent.dropped(job)
  end

  defp process_result({:fail, job, error, stack}) do
    log_error(job, error, stack)
    JobEvent.failed(job)
  end

  defp log_error(job, error, stack) do
    stacktrace = Exception.format_stacktrace(stack)
    job_details = "#{job.id}: #{inspect(job.worker)}.perform(#{inspect(job.args)})"

    "Job #{job_details} failed with error: #{inspect(error)}\n#{stacktrace}"
    |> String.trim
    |> Logger.error
  end
end
