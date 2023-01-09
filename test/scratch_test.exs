defmodule Scratch.MacrosTest do
  @moduledoc """
  xxx test
  """
  use ExUnit.Case
  doctest Scratch

  test "greets the world" do
    assert Scratch.hello() == :world
  end

  test "amac macro" do
    Scratch.amac(5 == (25/5))
  end

  test "multiplication rule" do
    p = quote do: 4*x**2 + 1*x + 16
    ddx = Scratch.del(p)
    #IO.inspect(ddx)

    IO.puts Macro.to_string(ddx)
  end


end
