defmodule Joq.JobProcess do
  require Logger

  defmodule CrashError do
    @moduledoc """
      Represents a process crash. Ensures we always return an error struct,
      even if the crash didn't occur from a raised error.

      Keeps the consuming code simple.
    """

    defexception message: "Job runner crashed"
  end

  def run(job) do
    Logger.debug("Running job #{job.id}")
    case run_job(job) do
      :ok ->
        Logger.debug("Job #{job.id} successfully run")
        {:success, job}
      {error, stack} ->
        # No logging here. These errors will be reported at a later stage
        {:fail, job, error, stack}
    end
  end

  defp run_job(job) do
    parent = self()

    spawn_monitor fn ->
      send parent, run_job_and_capture_result(job)
    end

    wait_for_result()
  end

  defp run_job_and_capture_result(job) do
    try do
      job.worker.perform(job.args)
      :success
    rescue
      error ->
        {:error, error, System.stacktrace}
    end
  end

  defp wait_for_result do
    receive do
      {:DOWN, _ref, :process, _pid, :normal} ->
        # both errors and successes result in a normal exit, wait for more information
        wait_for_result()
      {:DOWN, _ref, :process, _pid, error} -> # Failed beause the process crashed
        crash_error =
          CrashError.exception("The job runner crashed. Reason: #{inspect error}")

        {crash_error, []}
      {:error, error, stack} ->
        {error, stack}
      :success ->
        :ok
    end
  end
end
