defmodule Joq.JobQueue do
  use GenServer

  alias Joq.JobProcess

  # Our state is a map of worker => %{queue, running} associations
  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  "run" starts a job if the concurrency limit has not been reached and enqueues
  the job for later execution otherwise
  """
  def run(job) do
    if job.worker.max_concurrent == :infinity do
      # No need to enter into the queue
      run_job(job)
    else
      request_run(job)

      receive do
        {:run, job} ->
          result = run_job(job)
          confirm_run(job)
          result
      end
    end
  end

  defp run_job(job), do: JobProcess.run(job)

  defp request_run(job) do
    GenServer.cast(__MODULE__, {:request_run, job, self})
  end

  defp confirm_run(job) do
    GenServer.cast(__MODULE__, {:confirm_run, job})
  end

  def handle_cast({:request_run, job, caller}, state) do
    new_state =
      if can_run?(state, job) do
        run_now(state, {job, caller})
      else
        run_later(state, {job, caller})
      end
    {:noreply, new_state}
  end

  def handle_cast({:confirm_run, job}, state) do
    state = update_running(state, job, -1)

    new_state =
      if can_run?(state, job) do
        run_pending(state, job)
      else
        state
      end
    {:noreply, new_state}
  end

  defp run_pending(state, job) do
    get_worker_state(state, job).queue
    |> :queue.out()
    |> run_queued(state, job)
  end

  defp run_queued({:empty, _queue}, state, _previous), do: state
  defp run_queued({{:value, job}, queue}, state, previous_job) do
    state = run_now(state, job)

    new_worker_state = %{get_worker_state(state, previous_job) | queue: queue}
    put_worker_state(state, previous_job, new_worker_state)
  end

  defp run_now(state, {job, caller}) do
    send caller, {:run, job}
    
    update_running(state, job, +1)
  end

  defp run_later(state, {job, caller}) do
    worker_state = get_worker_state(state, job)
    queue = :queue.in({job, caller}, worker_state.queue)
    put_worker_state(state, job, %{worker_state | queue: queue})
  end

  # Running jobs count
  defp can_run?(state, job) do
    get_worker_state(state, job).running < job.worker.max_concurrent
  end

  defp update_running(state, job, delta) do
    running = get_worker_state(state, job).running + delta

    if running < 0 do
      raise "Job count should never be able to be less than zero, state is: #{inspect(state)}"
    end

    new_worker_state = %{get_worker_state(state, job) | running: running}
    put_worker_state(state, job, new_worker_state)
  end

  # Worker state helpers
  defp get_worker_state(state, job) do
    Map.get(state, job.worker, %{queue: :queue.new(), running: 0})
  end
  defp put_worker_state(state, job, new_state) do
    Map.put(state, job.worker, new_state)
  end
end
