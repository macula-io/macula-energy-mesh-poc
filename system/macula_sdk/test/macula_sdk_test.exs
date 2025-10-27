defmodule MaculaSdkTest do
  use ExUnit.Case
  doctest MaculaSdk

  test "greets the world" do
    assert MaculaSdk.hello() == :world
  end
end
