defmodule Joq.Retry do
  @moduledoc """
  Handles configuration for automatic retries of failed jobs.

  Retry configs can be specified at three levels:

    * In the global configuration, e.g. `config :joq, retry: [max_attempts: 3]`
    * Per worker module, e.g. `use Joq.Worker, retry: {:static, 250}`
    * Per job, e.g. `Joq.enqueue(MyWorker, [foo: 1], retry: :immediately)`

  Note that overlapping configs are merged, so if the global config specifies,
  for instance, `[max_attempts: 3, delay: 500]` and the job level config is
  `[max_attempts: 2, max_delay: 1000]`, the resulting config will be
  `[max_attempts: 2, delay: 500, max_delay: 1000, exponent: 4]`.

  Retry configs take the following fields:

    * `max_attempts` - the number of times that a job may be run if it fails.
      This doesn't count the initial run, so a job with `max_attempts: 3` will
      be run up to 4 times before it is marked as failed. Can be `nil` for
      infinite retries. Default: 5
    * `delay` - the delay before a job is run again in milliseconds. If
      exponential backoff is used, this will be the base delay. Default: 250 ms
    * `exponent` - the exponent that will be used for the calculation of delay.
      The delay is calculated as `pow(attempt, exponent) * delay`, so an
      exponent of 0 will give you a static delay (see also `retry_delay/2`).
      Default: 4
    * `max_delay` - the maximum delay for a job. This is used to cap the delay
      if exponential backoff is used. Can be `nil`. Default: 3600000 ms (1 hour)

  Retry configs can be specified as keyword lists or maps. Additionally, the
  following shortcuts exist:

    * `nil` or `[]` - use the default config
    * `:no_retry` - `max_attempts: 0`
    * `:immediately` - Retry without delay (`max_attempts` is a default of 5).
      This is similar to setting `delay: 0`
    * `{:immediately, max_attempts}` - Retry without delay, set `max_attempts`
    * `{:static, delay}` - Always retry with the same delay (`max_attempts` is
      the default value, 5). Similar to setting `exponent: 0`
    * `{:static, delay, max_attempts}` - Like the above but set `max_attempts`

  Invalid configs will raise an error.

  ## Examples

      # Don't retry failed jobs
      config :joq, retry: :no_retry

      # Retry failed jobs at most 3 times after a 4 second delay between tries
      config :joq, retry: {:static, 4000, 3}

      # Retry failed jobs without delay for 2 times (so in total, a job may be
      # run up to 3 times
      config :joq, retry: {:immediately, 2}

      # Retry failed jobs at most 4 times after (attempt^2) * 0.5 second delay.
      # That is, delays are 500, 2_000, 4_500, 8_000 ms before try 1, 2, 3, 4
      config :joq, retry: [exponent: 2, delay: 500, max_attempts: 4]
  """

  import Keyword, only: [drop: 2, take: 2, keys: 1]
  import Enum, only: [map: 2, join: 2]

  @options [exponent: 4, delay: 250, max_delay: 3_600_000, max_attempts: 5]
  defstruct @options

  @type t :: %__MODULE__{
    exponent: non_neg_integer,
    delay: non_neg_integer,
    max_delay: non_neg_integer | nil,
    max_attempts: non_neg_integer | nil
  }

  @type config ::
    [] | nil |
    :no_retry |
    :immediately |
    {:immediately, max_attempts :: non_neg_integer | nil} |
    {:static, delay :: non_neg_integer} |
    {:static, delay :: non_neg_integer, max_attempts :: non_neg_integer | nil} |
    %{required(atom) => non_neg_integer | nil} |
    keyword(non_neg_integer | nil)

  @doc """
  Used internally to create a Retry struct out of a config as specified
  above
  """
  @spec make_config(config) :: t
  def make_config(config) do
    override(%__MODULE__{}, config)
  end

  @doc """
  Used internally to override a Retry struct with another config
  """
  @spec override(t, config) :: t
  def override(original, nil), do: original
  def override(original, []), do: original

  def override(original, :no_retry), do: override(original, max_attempts: 0)

  def override(original, :immediately), do:
    override(original, delay: 0)
  def override(original, {:immediately, max_attempts}), do:
    override(original, delay: 0, max_attempts: max_attempts)

  def override(original, {:static, delay}), do:
    override(original, exponent: 0, delay: delay, max_delay: nil)
  def override(original, {:static, delay, max_attempts}), do:
    override(original, exponent: 0, delay: delay, max_delay: nil,
                       max_attempts: max_attempts)

  def override(original, %{} = conf), do: override(original, Map.to_list(conf))
  def override(original, config) do
    invalid_options = config |> drop(@options |> keys)

    if length(invalid_options) > 0 do
      invalid_keys = invalid_options |> keys |> map(&inspect/1) |> join(", ")
      valid_keys   =        @options |> keys |> map(&inspect/1) |> join(", ")

      raise ArgumentError, message: "Unknown retry option" <>
        "#{if length(invalid_options) > 1, do: "s"} #{invalid_keys}. Valid " <>
        "options are #{valid_keys}."
    end

    for {key, value} <- take(config, [:exponent, :delay]) do
      if not is_integer(value) or value < 0 do
        raise ArgumentError, message: "Invalid value, #{inspect(value)}, " <>
          "for retry option #{key}. Must be a non-negative integer."
      end
    end

    for {key, value} <- take(config, [:max_delay, :max_attempts]) do
      if value != nil and (not is_integer(value) or value < 0) do
        raise ArgumentError, message: "Invalid value, #{inspect(value)}, " <>
          "for retry option #{key}. Must be a non-negative integer or nil."
      end
    end

    original
    |> Map.merge(Map.new(config))
  end

  @doc """
  Whether to attempt another retry
  """
  @spec retry?(t, non_neg_integer) :: boolean
  def retry?(config, attempt), do: attempt <= config.max_attempts

  @doc """
  Returns the number of milliseconds to wait before the next attempt

  This delay is `pow(attempt, config.exponent) * config.delay`, but never higher
  than `config.max_delay`.

  For a static, non-increasing delay use an exponent of `0`. You can use `nil`
  for `max_delay` if you want no limit on the delay. The default is one hour.
  """
  @spec retry_delay(t, non_neg_integer) :: non_neg_integer
  def retry_delay(config, attempt) do
    delay = :math.pow(attempt, config.exponent) * config.delay

    if config.max_delay do
      trunc min(delay, config.max_delay)
    else
      trunc delay
    end
  end
end