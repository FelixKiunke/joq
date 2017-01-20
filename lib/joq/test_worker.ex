defmodule Joq.TestWorker do
  use Joq.Worker, max_concurrent: 1, retry: [delay: 500, exponent: 2, max_attempts: 3],
    duplicates: :drop

  # Usage: Joq.enqueue(Joq.TestWorker, :fail)
  #
  # To make this fail right away:
  # Application.put_env(:Joq, :retry_strategy, Joq.RetryWithoutDelayStrategy)
  def perform(:fail) do
    IO.inspect "Running fail-every-time job"
    raise "failing every time"
  end

  def perform(:fail_once) do
    unless Application.get_env(:Joq, :fail_once) do
      IO.inspect "failing once"
      Application.put_env(:Joq, :fail_once, true)
      raise "failing once"
    end

    IO.inspect "fail once job succeeded"
  end

  def perform([]) do
    IO.puts "Job started"
    :timer.sleep 3000
    IO.puts "Job finished"
  end
end