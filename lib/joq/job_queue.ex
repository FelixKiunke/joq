defmodule Joq.JobQueue do
  use GenServer
  require Logger

  alias Joq.JobProcess
  alias Joq.Job

  import Joq.Timing

  # Our state is a triple {state_map, delay_queue} where
  # - state_map is a map that maps worker modules to a {queue, running, ?}
  #   triple
  # - delay_queue is a sorted list of {timestamp, job, caller} triples where
  #   timestamp is the timestamp when the job should be executed
  def start_link do
    GenServer.start_link(__MODULE__, {%{}, []}, name: __MODULE__)
  end

  @doc """
  "run" starts a job if the concurrency limit has not been reached and enqueues
  the job for later execution otherwise
  """
  def run(job, delay \\ nil) do
    if delay == nil and job.worker.max_concurrent == :infinity do
      # No need to enter into the queue
      run_job(job)
    else
      request_run(job, delay && now() + delay)

      receive do
        {:run, job} ->
          result = run_job(job)
          confirm_run(job)
          result
        :drop ->
          {:dropped, job}
      end
    end
  end

  def get_state, do:
    GenServer.call(__MODULE__, :get_state)

  defp run_job(job), do: JobProcess.run(job)
  def handle_call(:get_state, _, state), do:
    {:reply, state, state}

  defp request_run(job, delay_until, caller \\ nil) do
    GenServer.cast(__MODULE__, {:request_run, job, delay_until, caller || self()})
  end

  defp confirm_run(job) do
    GenServer.cast(__MODULE__, {:confirm_run, job})
  end

  def handle_cast({:request_run, job, delay_until, caller}, state) do
    run_at = delay_until || job.delay_until
    new_state =
      cond do
        drop_dupes?(job) and dupe_running?(state, job) ->
          send caller, :drop
          state
        run_at && run_at > now() ->
          run_delayed(state, {job, caller}, run_at)
        can_run?(state, job) ->
          run_now(state, {job, caller})
        true ->
          run_later(state, {job, caller})
      end
    {:noreply, new_state}
  end

  def handle_cast({:confirm_run, job}, state) do
    new_state =
      state
      |> remove_from_running(job)
      |> run_pending(job.worker)

    {:noreply, new_state}
  end

  def handle_info(:run_delayed, {worker_states, delay_queue}) do
    ts = now()
    {run_now, run_later} =
      delay_queue
      |> Enum.partition(fn {run_at, _, _} -> run_at <= ts end)

    run_now
    |> Enum.each(fn {_, job, caller} ->
      # Remove delays and run the job (if running < max_concurrent)
      request_run(%{job | delay_until: nil}, nil, caller)
    end)

    {:noreply, {worker_states, run_later}}
  end

  defp run_delayed({worker_states, queue}, {job, caller}, run_at) do
    # Send a message when this job should be run. Due to the possibility of jobs
    # being dropped, too many :run_delayed messages may be sent. This is not a
    # problem as these messages will be ignored if there are no jobs to be run
    # at the point that a message is sent
    Process.send_after(__MODULE__, :run_delayed, max(run_at - now(), 0))

    new_queue =
      if drop_dupes?(job) do
        {dupes, others} =
          [{run_at, job, caller} | queue]
          |> Enum.partition(fn {_run_at, q_job, _caller} ->
            Job.is_equal(job, q_job)
          end)

        dupes =
          dupes
          |> Enum.sort_by(fn {run_at, _job, _caller} -> run_at end)

        # Drop duplicates that are to be run later than the soonest job
        dupes
        |> Enum.drop(1)
        |> Enum.each(fn {_run_at, _job, caller} -> send caller, :drop end)

        [Enum.at(dupes, 0) | others] 
      else
        [{run_at, job, caller} | queue]
      end 

    {worker_states, new_queue}
  end

  defp run_now(state, {job, caller}) do
    send caller, {:run, job}
    
    state
    |> drop_dupes_from_queue(job)
    |> add_to_running(job)
  end

  defp run_later(state, {job, caller}) do
    Logger.debug("Job #{job.id} postponed (concurrency limit has been reached)")

    state
    |> update_worker_state(job, fn %{queue: queue} = ws ->
      %{ws | queue: :queue.in({job, caller}, queue)}
    end)
    |> drop_dupes_from_queue(job)
  end

  defp run_pending(state, worker) do
    get_worker_state(state, worker).queue
    |> :queue.out()
    |> case do
      {:empty, _queue} ->
        state
      {{:value, job_and_caller}, new_queue} ->
        state
        |> update_worker_state(worker, %{queue: new_queue})
        |> run_now(job_and_caller)
    end
  end

  defp drop_dupes?(job) do
    job.worker.duplicate_config == :drop
  end

  # Returns true if a duplicate of job is already running or enqueued
  defp dupe_running?(state, job) do
    worker_state = get_worker_state(state, job)

    (worker_state.running
     |> Enum.find(fn r_job -> Job.is_equal(r_job, job) end)) != nil or
    (worker_state.queue
     |> :queue.to_list
     |> Enum.find(fn {q_job, _caller} -> Job.is_equal(q_job, job) end)) != nil
  end

  # Deletes dupes from the list of delayed jobs if duplicates should be dropped
  defp drop_dupes_from_queue({worker_states, delay_queue} = state, job) do
    if drop_dupes?(job) do
      new_queue =
        delay_queue
        |> Enum.reject(fn {_run_at, q_job, q_caller} ->
          if Job.is_equal(job, q_job) do
            send q_caller, :drop
            true
          end
        end)

      {worker_states, new_queue}
    else
      state
    end
  end

  # Running jobs count
  defp can_run?(state, %Job{worker: worker}), do: can_run?(state, worker)
  defp can_run?(state, worker) do
    length(get_worker_state(state, worker).running) < worker.max_concurrent
  end

  # Add a job to the list of running jobs for that worker
  defp add_to_running(state, job) do
    update_worker_state(state, job, fn %{running: running} = ws ->
      %{ws | running: [job | running]}
    end)
  end

  # Remove a job from the list of running jobs for that worker
  defp remove_from_running(state, job) do
    update_worker_state(state, job, fn %{running: running} = ws ->
      %{ws | running: List.delete(running, job)}
    end)
  end

  # Worker state helpers
  defp get_worker_state(state, %Job{worker: worker}), do:
    get_worker_state(state, worker)
  defp get_worker_state({worker_states, _delay_queue}, worker) do
    Map.get(worker_states, worker, %{queue: :queue.new(), running: []})
  end

  defp put_worker_state(state, %Job{worker: worker}, new), do:
    put_worker_state(state, worker, new)
  defp put_worker_state({worker_states, delay_queue}, worker, new_state) do
    {Map.put(worker_states, worker, new_state), delay_queue}
  end

  defp update_worker_state(state, %Job{worker: worker}, changes), do:
    update_worker_state(state, worker, changes)
  defp update_worker_state(state, worker, %{} = changes), do:
    update_worker_state(state, worker, fn map -> Map.merge(map, changes) end)
  defp update_worker_state(state, worker, fun) when is_function(fun) do
    new_state =
      get_worker_state(state, worker)
      |> fun.()
    put_worker_state(state, worker, new_state)
  end
end
