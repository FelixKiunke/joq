defmodule JoqTest do
  use ExUnit.Case

  defmodule TestWorker do
    use Joq.Worker

    def perform(data: value) do
      send :joq_test, {:job_run, data: value}
    end
  end

  defmodule ErrorTestWorker do
    use Joq.Worker

    def perform(data: number) do
      send :joq_test, {:job_run, data: number}
      raise "fail"
    end
  end
end