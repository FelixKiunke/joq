defmodule Joq.Worker do
  import Keyword, only: [drop: 2, keys: 1]
  import Enum, only: [map: 2, join: 2]

  alias Joq.Retry

  defmacro __using__(options \\ []) do

    invalid_options = drop(options, [:max_concurrent, :retry, :duplicates])

    if length(invalid_options) > 0 do
      invalid_keys = invalid_options |> keys |> map(&inspect/1) |> join(", ")

      raise "Unknown option#{if length(invalid_options) > 1, do: "s"} " <>
        "#{invalid_keys}. Valid options are max_concurrent, retry, duplicates."
    end

    # Throw errors for invalid configs
    Retry.make_config(options[:retry])

    quote do
      # Perform without arguments when called with an empty argument list
      def perform([]) do
        perform()
      end

      def max_concurrent do
        unquote(options[:max_concurrent] || :infinity)
      end

      def retry_config do
        unquote(Macro.escape(options[:retry]))
      end

      def duplicate_config do
        unquote(options[:duplicates] || :accept)
      end

      defoverridable [perform: 1]
    end
  end
end
