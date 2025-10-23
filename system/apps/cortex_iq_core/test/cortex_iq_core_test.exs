defmodule CortexIqCoreTest do
  use ExUnit.Case
  doctest CortexIqCore

  test "greets the world" do
    assert CortexIqCore.hello() == :world
  end
end
