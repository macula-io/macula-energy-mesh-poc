defmodule MaculaGatewayServiceTest do
  use ExUnit.Case
  doctest MaculaGatewayService

  test "greets the world" do
    assert MaculaGatewayService.hello() == :world
  end
end
