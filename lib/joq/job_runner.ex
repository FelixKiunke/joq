defmodule Joq.JobRunner do
  use GenServer
  require Logger

  alias Joq.JobQueue
  alias Joq.JobEvent
  alias Joq.Retry

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register_job(job) do
    GenServer.cast(__MODULE__, {:register_job, job})
  end

  def handle_cast({:register_job, job}, state) do
    spawn_link fn ->
      job
      |> run_job
      |> retry_failed
      |> process_result
    end

    {:noreply, state}
  end

  defp run_job(job), do: JobQueue.run(job)

  defp retry_failed(status), do: retry_failed(status, 1)
  defp retry_failed({:success, job}, _attempt), do: {:success, job}
  defp retry_failed({:fail, job, error, stack}, attempt) do
    retry_config =
      Application.get_env(:joq, :retry)
      |> Retry.make_config()
      |> Retry.override(job.worker.retry_config)
      |> Retry.override(job.retry)

    if Retry.retry?(retry_config, attempt) do
      :timer.sleep Retry.retry_delay(retry_config, attempt)

      run_job(job)
      |> retry_failed(attempt + 1)
    else
      {:fail, job, error, stack}
    end
  end

  defp process_result({:success, job}) do
    JobEvent.finished(job)
  end

  defp process_result({:fail, job, error, stack}) do
    log_error(job, error, stack)
    JobEvent.failed(job)
  end

  defp log_error(job, error, stack) do
    stacktrace = Exception.format_stacktrace(stack)
    job_details = "##{job.id}: #{inspect(job.worker)}.perform(#{inspect(job.args)})"

    "Job #{job_details} failed with error: #{inspect(error)}\n\n#{stacktrace}"
    |> String.trim
    |> Logger.error
  end
end
