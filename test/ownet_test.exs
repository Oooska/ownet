defmodule OwnetTest do
  use ExUnit.Case
  doctest Ownet

  test "greets the world" do
    assert Ownet.hello() == :world
  end
end
