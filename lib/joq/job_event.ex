defmodule Joq.JobEvent do
  @moduledoc ~S"""
  Reports events from the job running lifecycle.

  Events are `{result, job}` messages where `job` is a `Joq.Job` struct and
  `result` can be

    * `:finished` - the job was completed successfully,
    * `:failed` - an error has occurred (note this event after the last attempt
      if a job may be retried)
    * `:dropped` - the job was removed from the queue as a duplicate (only if
      the job's worker has `duplicates: :drop` set, see `Joq.Worker`)

  These events are sent to all subscribed processes as regular messages.

  ## Example

      Joq.JobEvent.subscribe
      receive do
        {:finished, job} ->
          IO.puts("Hooray, job #{job.id} was completed successfully")
        {:failed, job} ->
          IO.puts("Booo, job #{job.id} failed")
        {:dropped, job} ->
          IO.puts("Job #{job.id} was a dupe and has been dropped")
      end
      # Note that events will be sent until we unsubscribe
      Joq.JobEvent.unsubscribe
  """

  use GenServer

  @doc false
  def start_link do
    {:ok, _pid} =
      GenServer.start_link(__MODULE__, %{listeners: []}, name: __MODULE__)
  end

  @doc """
  Subscribes the current process to events.
  """
  def subscribe do
    GenServer.call(__MODULE__, :subscribe)
  end

  @doc """
  Unsubscribes the current process.
  """
  def unsubscribe do
    GenServer.call(__MODULE__, :unsubscribe)
  end

  def handle_call(:subscribe, {caller, _ref}, state) do
    state = Map.put(state, :listeners, state.listeners ++ [caller])
    {:reply, :ok, state}
  end

  def handle_call(:unsubscribe, {caller, _ref}, state) do
    state = Map.put(state, :listeners, state.listeners -- [caller])
    {:reply, :ok, state}
  end

  def handle_cast({:notify, event}, state) do
    Enum.each state.listeners, fn (pid) ->
      send pid, event
    end

    {:noreply, state}
  end

  @doc false
  # Send a :finished event
  @spec finished(Joq.Job.t) :: term
  def finished(job) do
    notify {:finished, job}
  end

  @doc false
  # Send a :dropped event
  @spec dropped(Joq.Job.t) :: term
  def dropped(job) do
    notify {:dropped, job}
  end

  @doc false
  # Send a :failed event
  @spec failed(Joq.Job.t) :: term
  def failed(job) do
    notify {:failed, job}
  end

  defp notify(event) do
    GenServer.cast(__MODULE__, {:notify, event})
  end
end
