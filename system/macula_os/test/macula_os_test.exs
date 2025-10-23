defmodule MaculaOsTest do
  use ExUnit.Case
  doctest MaculaOs

  test "greets the world" do
    assert MaculaOs.hello() == :world
  end
end
