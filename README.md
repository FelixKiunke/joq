Joq
===

## NOTE: This Readme is out of date!

Simple and reliable background job queue library for [Elixir](http://elixir-lang.org/).

* Focuses on being easy to use and handling errors well.
* Will automatically retry failing jobs a few times.
* It has practically no limits on concurrent jobs.
* Can limit concurrency using a max concurrency option.
* Passes arguments to the worker exactly as they where enqueued, no JSON conversion.
* Fails on the side of running a job too many times rather than not at all. See more on this below.
* No persistence!

If anything is unclear about how this library works or what an error message means **that's considered a bug**, please file an issue (or a pull request)!

--

Note: this is partly based on [toniq](https://github.com/joakimk/toniq), which
requires Redis and supports persistence.

## Installation

Add as a dependency in your mix.exs file:

```elixir
defp deps do
  [
    {:joq, "~> 0.1"}
  ]
end
```

And run:

    mix deps.get

Then add `:joq` to the list of applications in mix.exs.

## Usage

Define a worker:

```elixir
defmodule SendEmailWorker do
  use Joq.Worker

  def perform(to: to, subject: subject, body: body) do
    # do work
  end
end
```

Enqueue jobs somewhere in your app code:

```elixir
Joq.enqueue(SendEmailWorker, to: "info@example.com", subject: "Hello", body: "Hello, there!")
```

## Pipelines

You can also enqueue jobs using |> like this:

```elixir
email = [to: "info@example.com", subject: "Hello", body: "Hello, there!"]

email
|> Joq.enqueue_to(SendEmailWorker)
```

## Delayed jobs

And delay jobs.

```elixir
email = [to: "info@example.com", subject: "Hello", body: "Hello, there!"]

# Using enqueue_to:
email
|> Joq.enqueue_to(SendEmailWorker, delay_for: 1000)

# Using enqueue_with_delay:
Joq.enqueue_with_delay(SendEmailWorker, email, delay_for: 1000)
```

## Pattern matching

You can pattern match in workers. This can be used to clean up the code, or to handle data from previous versions of the same worker!

```elixir
defmodule SendMessageWorker do
  use Joq.Worker

  def perform(message: "", receipient: _receipient) do
    # don't send empty messages
  end

  def perform(message: message, receipient: receipient) do
    SomeMessageService.send(message, receipient)
  end
end
```

## Limiting concurrency

For some workers you might want to limit the number of jobs that run at the same time. For example, if you call out to a API, you most likely don't want more than 3-10 connections at once.

You can set this by specifying the `max_concurrency` option on a worker.

```elixir
defmodule RegisterInvoiceWorker do
  use Joq.Worker, max_concurrency: 10

  def perform(attributes) do
    # do work
  end
end
```

## Retrying failed jobs

An admin web UI is planned, but until then (and after that) you can use the console.

Retrying all failed jobs:

```elixir
iex -S mix
iex> Joq.failed_jobs |> Enum.each &Joq.retry/1
```

Retrying one at a time:

```elixir
iex> job = Joq.failed_jobs |> hd
iex> Joq.retry(job)
```

Or delete the failed job:

```elixir
iex> job = Joq.failed_jobs |> hd
iex> Joq.delete(job)
```

## Automatic retries

Jobs will be retried automatically when they fail. This can be customized or disabled.

The default strategy is exponential retry, which will retry a job 5 times after the initial run with increasing delay between each. Delays are approximately: 250 ms, 1 second, 20 seconds, 1 minute and 2.5 minutes, that is `min(pow(attempt, 4) * 250, 3600000)`. See below example for default values. `max_delay` and `max_attempts` can be :infinite.

An alternative is `:static`, which always uses a constant delay between attempts. The default is 500 ms, but if you want to retry immediately, use 0.

This can be overriden per job by specifying the retry option in enqueue.

```elixir
config :joq, retry: :no_retry
confiq :joq, retry: [timing: :static, delay: 250, max_attempts: 5]
confiq :joq, retry: [timing: :exponential, exponent: 4, delay: 250, max_delay: 3600000, max_attempts: 5]
```

## Designed to avoid complexity

Joq does not use persistence. Jobs are run within the VM where they are enqueued. If a VM is stopped or crashes, unprocessed jobs are lost forever. Adjust accordingly!

## FAQ

### Why have a job queue at all?

* You don't have to run the code synchronously. E.g. don't delay a web response while sending email.
* You don't have to write custom code for the things a job queue can handle for you.
* You get persistence, retries, failover, concurrency limits, etc.

### Will jobs be run in order?

This is a first-in-first-out queue but due to retries and concurrency, ordering can not be guaranteed.

### If an Erlang VM stops with unprocessed jobs in its queue, how are those jobs handled?

All jobs are lost. So be careful and have some other way in place to recover important jobs. If you need persistence, you are better off using another library

### Why will jobs be run more than once in rare cases?

If something really unexpected happens and a job can't be marked as finished after being run, this library prefers to run it twice (or more) rather than not at all.

Unexpected things include something like an unexpected crash within the job runner.

You can solve this in two ways:
* Go with the flow: make your jobs runnable more than once without any bad sideeffects. Also known as [Reentrancy](https://en.wikipedia.org/wiki/Reentrancy_(computing)).
* Implement your own locking.

I tend to prefer the first alternative in whenever possible.

### How do I run scheduled or recurring jobs?

There is no built-in support yet, but you can use tools like <https://github.com/c-rack/quantum-elixir> to schedule joq jobs.

```elixir
config :quantum, cron: [
  # Every 15 minutes
  "*/15 * * * *": fn -> Toniq.enqueue(SomeWorker) end
]
```

## Versioning

This library uses [semver](http://semver.org/) for versioning. The API won't change in incompatible ways within the same major version, etc. The version is specified in [mix.exs](mix.exs).

## Credits

- This library is partly based on the [toniq](https://github.com/joakimk/toniq) library that supports persistence via Redis.
- The name joq is somewhat derived from toniq. Joq stands for job queue and is pronounced like jog.

## Contributing

* Pull requests:
  - Are very welcome :)
  - Should have tests
  - Should have refactored code that conforms to the style of the project (as best you can)
  - Should have updated documentation
  - Should implement or fix something that makes sense for this library (feel free to ask if you are unsure)
  - Will only be merged if all the above is fulfilled. I will generally not fix your code, but I will try and give feedback.
* If this project ever becomes too inactive, feel free to ask about taking over as maintainer.

## Development

    mix deps.get
    mix test

You can also try joq in dev using [Joq.TestWorker](lib/joq/test_worker.ex).

    iex -S mix
    iex> Joq.enqueue(Joq.TestWorker)
    iex> Joq.enqueue(Joq.TestWorker, :fail_once)

## TODO and ideas for after 1.0

* [ ] DOCS & TESTS
* [ ] Log an error when a job takes "too long" to run, set a sensible default
  - Not detecting this has led to production issues in other apps. A warning is easy to do and can help a lot.
* [ ] More logging
* [ ] Custom retry stategies per worker
* [ ] Add timeouts for jobs (if anyone needs it). Should be fairly easy.

## License

Copyright (c) 2017 [Felix Kiunke](https://fkiunke.de)

MIT License

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
