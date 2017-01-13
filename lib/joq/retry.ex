defmodule Joq.Retry do
  @options [exponent: 4, delay: 250, max_delay: 3600000, max_attempts: 5]

  defstruct @options

  import Keyword, only: [drop: 2, take: 2, keys: 1]
  import Enum, only: [map: 2, join: 2]

  def make_config(config) do
    override(%__MODULE__{}, config)
  end

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

      raise "Unknown retry option#{if length(invalid_options) > 1, do: "s"} " <>
        "#{invalid_keys}. Valid options are #{valid_keys}."
    end

    for {key, value} <- take(config, [:exponent, :delay]) do
      if not is_integer(value) or value < 0 do
        raise "Invalid value, #{inspect(value)}, for retry option #{key}" <>
          "Must be a non-negative integer."
      end
    end

    for {key, value} <- take(config, [:max_delay, :max_attempts]) do
      if value != nil and (not is_integer(value) or value < 0) do
        raise "Invalid value, #{inspect(value)}, for retry option #{key}" <>
          "Must be a non-negative integer or nil."
      end
    end

    original
    |> Map.merge(Map.new(config))
  end

  @doc """
  Whether to attempt another retry
  """
  def retry?(config, attempt), do: attempt <= config.max_attempts

  @doc """
  Returns the number of milliseconds to wait before the next attempt

  This delay is `pow(attempt, config.exponent) * config.delay`, but never higher
  than `config.max_delay`.

  For a static, non-increasing delay use an exponent of `0`. You can use `nil`
  for `max_delay` if you want no limit on the delay. The default is one hour.
  """
  def retry_delay(config, attempt) do
    delay = :math.pow(attempt, config.exponent) * config.delay

    if config.max_delay do
      trunc min(delay, config.max_delay)
    else
      trunc delay
    end
  end
end