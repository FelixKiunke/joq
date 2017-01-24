defmodule JobTest do
  use ExUnit.Case, async: true

  alias Joq.Job

  defmodule TestWorker do
  end

  test "creates a job with empty options" do
    job = Job.make("a", TestWorker, :foo)
    assert job == %Job{id: "a", worker: TestWorker, args: :foo,
                       retry: nil, delay_until: nil}
  end

  test "creates a job with retry config" do
    job = Job.make("b", TestWorker, :foo, retry: [exponent: 3, delay: 42])
    assert job == %Job{id: "b", worker: TestWorker, args: :foo,
                       retry: [exponent: 3, delay: 42], delay_until: nil}
  end

  test "creates a delayed job" do
    job = Job.make("c", TestWorker, :foo, delay_for: 3_000)
    exp = System.monotonic_time(:milli_seconds) + 3_000

    assert job.id == "c"
    assert job.worker == TestWorker
    assert job.args == :foo
    assert job.retry == nil
    assert_in_delta(job.delay_until, exp, 100)
  end

  test "compares if two jobs are equal" do
    a = Job.make("a", TestWorker, :foo)
    b = Job.make("b", TestWorker, :foo, delay_for: 3_000)
    c = Job.make("c", TestWorker, :foo, retry: :immediately)
    d = Job.make("d", TestWorker, :bar)
    e = Job.make("e", Something, :foo)

    assert Job.is_equal(a, b)
    assert Job.is_equal(b, a)
    assert Job.is_equal(a, c)
    assert Job.is_equal(b, c)
    refute Job.is_equal(a, d)
    refute Job.is_equal(a, e)
  end
end