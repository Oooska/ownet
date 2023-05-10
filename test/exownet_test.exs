defmodule ExownetTest do
  use ExUnit.Case
  doctest Exownet

  test "greets the world" do
    assert Exownet.hello() == :world
  end
end
