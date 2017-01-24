defmodule RetryTest do
  use ExUnit.Case, async: true

  alias Joq.Retry

  test "make_config/1 creates correct Retry structs" do
    base = %Retry{exponent: 4, delay: 250, max_delay: 3_600_000, max_attempts: 5}
    assert Retry.make_config(nil) == base
    assert Retry.make_config([]) == base
    assert Retry.make_config(:no_retry) == %{base | max_attempts: 0}
    assert Retry.make_config(:immediately) == %{base | delay: 0}
    assert Retry.make_config({:immediately, 42}) == %{base | delay: 0, max_attempts: 42}
    assert Retry.make_config({:static, 42}) == %{base | delay: 42, exponent: 0, max_delay: nil}
    assert Retry.make_config({:static, 42, 43}) == %{base | delay: 42, exponent: 0, max_delay: nil, max_attempts: 43}
    assert Retry.make_config(%{exponent: 42}) == %{base | exponent: 42}
    assert Retry.make_config(%{max_attempts: nil}) == %{base | max_attempts: nil}
    assert Retry.make_config(max_delay: 1, delay: 2) == %{base | delay: 2, max_delay: 1}
  end

  test "override/2 updates Retry structs correctly" do
    base = %Retry{exponent: 10, delay: 20, max_delay: 30, max_attempts: 40}
    assert Retry.override(base, nil) == base
    assert Retry.override(base, []) == base
    assert Retry.override(base, :no_retry) == %{base | max_attempts: 0}
    assert Retry.override(base, :immediately) == %{base | delay: 0}
    assert Retry.override(base, {:immediately, 42}) == %{base | delay: 0, max_attempts: 42}
    assert Retry.override(base, {:static, 42}) == %{base | delay: 42, exponent: 0, max_delay: nil}
    assert Retry.override(base, {:static, 42, 43}) == %{base | delay: 42, exponent: 0, max_delay: nil, max_attempts: 43}
    assert Retry.override(base, %{exponent: 42}) == %{base | exponent: 42}
    assert Retry.override(base, %{max_attempts: nil}) == %{base | max_attempts: nil}
    assert Retry.override(base, max_delay: 1, delay: 2) == %{base | delay: 2, max_delay: 1}
  end

  test "make_config/1 and override/2 raise on invalid keys" do
    assert_raise ArgumentError, fn -> Retry.make_config(foo: :invalid) end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, foo: :invalid) end
  end

  test "make_config/1 and override/2 raise on nil where not allowed" do
    assert_raise ArgumentError, fn -> Retry.make_config(delay: nil) end
    assert_raise ArgumentError, fn -> Retry.make_config(exponent: nil) end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, delay: nil) end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, exponent: nil) end
  end

  test "make_config/1 and override/2 raise on negative values where not allowed" do
    assert_raise ArgumentError, fn -> Retry.make_config(delay: -1) end
    assert_raise ArgumentError, fn -> Retry.make_config(exponent: -1) end
    assert_raise ArgumentError, fn -> Retry.make_config(max_delay: -1) end
    assert_raise ArgumentError, fn -> Retry.make_config(max_attempts: -1) end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, delay: -1) end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, exponent: -1) end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, max_delay: -1) end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, max_attempts: -1) end
  end

  test "make_config/1 and override/2 raise on other invalid values" do
    assert_raise ArgumentError, fn -> Retry.make_config(delay: :foo) end
    assert_raise ArgumentError, fn -> Retry.make_config(exponent: "bar") end
    assert_raise ArgumentError, fn -> Retry.make_config(max_delay: 2.5) end
    assert_raise ArgumentError, fn -> Retry.make_config(max_attempts: true) end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, delay: :foo) end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, exponent: "bar") end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, max_delay: 2.5) end
    assert_raise ArgumentError, fn -> Retry.override(%Retry{}, max_attempts: true) end
  end

  test "retry?/2 returns correct values" do
    conf1 = %Retry{max_attempts: 0}
    conf2 = %Retry{max_attempts: 5}
    assert Retry.retry?(conf1, 1) == false
    assert Retry.retry?(conf1, 9) == false
    assert Retry.retry?(conf2, 1) == true
    assert Retry.retry?(conf2, 5) == true
    assert Retry.retry?(conf2, 9) == false
  end

  test "retry_delay/2 computes correct delays" do
    conf1 = %Retry{exponent: 0, delay: 500, max_delay: 400}
    conf2 = %Retry{exponent: 0, delay: 500, max_delay: nil}
    conf3 = %Retry{exponent: 1, delay: 500, max_delay: nil}
    conf4 = %Retry{exponent: 1, delay: 500, max_delay: 1000}
    conf5 = %Retry{exponent: 3, delay: 500, max_delay: 1000}
    conf6 = %Retry{exponent: 3, delay: 500, max_delay: nil}
    conf7 = %Retry{exponent: 5, delay: 0, max_delay: nil}
    assert Retry.retry_delay(conf1, 1) == 400
    assert Retry.retry_delay(conf1, 5) == 400
    assert Retry.retry_delay(conf2, 1) == 500
    assert Retry.retry_delay(conf2, 5) == 500
    assert Retry.retry_delay(conf3, 1) == 500
    assert Retry.retry_delay(conf3, 5) == 2_500
    assert Retry.retry_delay(conf4, 1) == 500
    assert Retry.retry_delay(conf4, 5) == 1_000
    assert Retry.retry_delay(conf5, 1) == 500
    assert Retry.retry_delay(conf5, 5) == 1_000
    assert Retry.retry_delay(conf6, 1) == 500
    assert Retry.retry_delay(conf6, 5) == 62_500
    assert Retry.retry_delay(conf7, 1) == 0
    assert Retry.retry_delay(conf7, 5) == 0
  end
end