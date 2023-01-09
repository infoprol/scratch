defmodule Scratch.DinPhil do
  @moduledoc """
  dining philosophers
  """




  defmodule Chopstick do
    @moduledoc """
    a chopstick that should be as fair as elixir mailboxes are,
    errrrr, roughly anyway.

    just a simple agent-based mutex.

    ## message protocol (in the general sense of "protocol", not an elixir Protocol)

        iex> c = Scratch.DinPhil.Chopstick.init()
        iex> me = self()
        iex> someother_pid = spawn(fn ->
          receive do
            {:chopstick_acquired, ^c} -> IO.puts("some other pid acquired the chopstick")
          end
        end)
        iex> send(c, {:acquire, me})
        iex> send(c, {:acquire, someother_pid})
        iex> receive do
          {:chopstick_acquired, ^c} -> IO.puts("iex acquired chopstick")
        end

        iex acquired chopstick
        :ok
        iex> send(c, {:release, me})

        some other pid acquired the chopstick

        iex> receive do
          {:chopstick_released, ^c} -> "iex process has released chopstick"

        iex process has released chopstick
    """
alias Scratch.DinPhil.Chopstick

    @type t :: %__MODULE__{
      outputer: pid(),
    }
    defstruct [outputer: nil]

    def output(%Chopstick{outputer: o}, msg) do
      send(o, "chopstick #{self()}: #{msg}")
    end

    def init(outputer) do
      c_pid = spawn(
        fn ->
          available(%Chopstick{
            outputer: outputer,
          })
        end)
      c_pid
    end

    def available(%Chopstick{} = c) do

    end

  end





  defmodule Philosopher do
    @moduledoc """
    philosopher actor - really, this should probably be an agent.
    went with coding it this way though, at least initially, so that
    all the receive logic would be explicit.
    """
    @type t :: %__MODULE__{
      id:   String.t(),
      total_rice_eaten: integer(),

      left_chopstick: pid(),
      right_chopstick: pid(),
      bowl_of_rice: pid(),

      outputer: pid(),
    }
    defstruct [
      id: nil,
      total_rice_eaten: 0,
      left_chopstick: nil,
      right_chopstick: nil,
      bowl_of_rice: nil,
      outputer: nil,
    ]

    @eat_delay_sec 2

    def output(%Philosopher{id: id, outputer: o}, msg), do: send(o, "philosopher '#{id}': #{msg}.")

    def release_chopsticks(%Philosopher{
      left_chopstick: l,
      right_chopstick: r,
    } = p) do
      send(l, {:release, self()})
      send(r, {:release, self()})

      receive do
        {:chopstick_released, ^l} ->
          output(p, "left chopstick #{l} relased.")
      end
      receive do
        {:chopstick_released, ^r} ->
          output(p, "right chopstick #{r} released.")
      end
    end

    def doneyet(%Philosopher{
        total_rice_eaten: total_rice_eaten,} = p) do

      release_chopsticks(p)
      output(p,
        "doneyet -> #{total_rice_eaten} total rices eaten.")
    end

    # tail recursive functions for various states
    # @spec eat(t()) :: nil
    def eat(%Philosopher{
        bowl_of_rice: bowl_of_rice,
        total_rice_eaten: total_rice_eaten} = p, curr_rice_to_eat) do

      output(p, "eating with #{curr_rice_to_eat} left to go...")

      :timer.sleep(:timer.seconds(@eat_delay_sec))
      send(
        bowl_of_rice,
        {:eat, curr_rice_to_eat})

      receive do
        {:bowl_is_empty} -> doneyet(p)
        {:rice, n} ->
          case {curr_rice_to_eat - n, total_rice_eaten + n} do
            {new_curr, new_total} when new_curr < 1 ->
              release_chopsticks(p)
              think(
                %{p | total_rice_eaten: new_total})
            {new_curr, new_total} ->
              eat(
                %{p | total_rice_eaten: new_total},
                new_curr)
          end
      end
    end # eat(..)

    # @spec acquire_right(t()) :: nil
    def acquire_right(%Philosopher{right_chopstick: right_chop} = p, curr_rice_to_eat) do
      output(p, "acquiring right chopstick...")
      send(
        right_chop,
        {:aquire, self()})
      receive do
        {:chopstick_acquired, ^right_chop} ->
          eat(p, curr_rice_to_eat)
      end
    end

    # @spec acquire_left(t()) :: nil
    def acquire_left(%Philosopher{left_chopstick: left_chop} = p, curr_rice_to_eat) do
      output(p, "acquiring left chopstick...")
      send(
        left_chop,
        {:aquire, self()})
      receive do
        {:chopstick_aquired, ^left_chop} ->
            acquire_right(p, curr_rice_to_eat)
      end
    end

    # @spec thinking(t()) :: nil
    def think(p) do
      output(p, "thinking...")
      receive do
        {:become_hungry, to_eat} ->
          acquire_left(p, to_eat)
      end
    end

    def init(id, l, r, bowl, o) do
      phil_pid = spawn(
        fn -> think(%Philosopher{
          id: id,
          left_chopstick: l,
          right_chopstick: r,
          total_rice_eaten: o,
          bowl_of_rice: bowl,
          outputer: o,
        }) end)
    end

  end #module Scratch.DinPhil.Philosopher
end #module Scratch.DinPhil
