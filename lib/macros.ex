defmodule Scratch.Macros do
  @moduledoc """
  Documentation for `Scratch`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Scratch.hello()
      :world

  """
  def hello do
    :world
  end


  defmacro amac(params) do
    IO.puts "inside amac/1 macro."
    IO.inspect params

    ans = quote do
      param_val = unquote(params)
      IO.puts "this will be injected into the caller's context. param_val is #{param_val}."
      :os.system_time(:seconds)
    end

    IO.puts "amac/1 answer:"
    IO.inspect ans

    ans
  end

  @doc """
  wreckless direct manipulation of AST nodes."
  """
  def del({:+, ctx, [lhs, rhs]}) do
    {:+,
      ctx,
      [
        {:*,
          ctx,
          [lhs, del(rhs)]},
        {:*,
          ctx,
          [del(rhs), lhs]},
      ]
    }
  end
  def del(x), do: x


end
