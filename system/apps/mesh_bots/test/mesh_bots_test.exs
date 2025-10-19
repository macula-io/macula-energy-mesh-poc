defmodule MeshBotsTest do
  use ExUnit.Case
  doctest MeshBots

  test "greets the world" do
    assert MeshBots.hello() == :world
  end
end
