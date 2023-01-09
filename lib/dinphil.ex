defmodule Scratch.DinPhil do
  @moduledoc """
  dining philosophers
  """


  defmodule BowlOfRice do
    @moduledoc """
    when philosophers try to eat from this bowl, the bowl will give
    bite_size grains of rice per :eat msg
    """

    @bite_size 10

    def output({_, o}, msg),
      do: send(o, {self(), msg})

    def serve_rice({rice_count, o} = bowl_state) do
      receive do
        {:doneyet} when rice_count > 0 ->
          output(bowl_state, "hey there is still rice in the bowl!  we are not doneyet!")
          serve_rice(bowl_state)
        {:eat, eating_pid} ->
          case rice_count do
            rice_count when rice_count == 0 ->
              send(eating_pid, :bowl_is_empty)
              serve_rice({0, o})
            rice_count when rice_count < @bite_size ->
              send(eating_pid, rice_count)
              serve_rice({0, o})
            rice_count ->
              send(eating_pid, @bite_size)
              serve_rice({rice_count - @bite_size, o})
          end
      end
    end

    def start_link({rice_count, outputer}) do
      bowl = spawn(fn -> serve_rice({rice_count, outputer}) end)
      {:ok, bowl}
    end
  end


  #TODO register this process with a Registry name, take out all the manual passing of its pid.
  defmodule Outputer do
    @moduledoc """
    simple process to serialize writing to output

    expects a message to either be
      {from_pid, msg}

      or

      {:doneyet}

    ## example

      iex> o = Outputer.startup()
      "2023-01-09T07:04:53.358281Z|<0.148.0>|outputer started."
      iex> send(o, {self(), "hello is this thing on?"})
      "2023-01-09T07:05:57.666975Z|<0.148.0>|hello is this thing on?"
      iex> send(o, {:doneyet})
      "2023-01-09T07:06:41.575905Z|<0.148.0>|OUTPUT ENDS"

    """

    def startup() do
      out_pid = spawn(fn -> loop() end)
    end

    def to_line(msg) do
      "{DateTime.utc_now |> DateTime.to_iso8601}|#{msg}"
    end
    def to_line(from_pid, msg) do
      "{DateTime.utc_now |> DateTime.to_iso8601}|#{:erlang.pid_to_list(from_pid)}|#{msg}"
    end

    def doneyet() do
      send(self(), "OUTPUT ENDS")
    end

    def loop() do
      send(self(), "outputer started.")

      receive do
        {:doneyet} -> doneyet()
        {from_pid, msg} -> IO.puts(to_line(from_pid, msg))
        msg when is_binary(msg) -> IO.puts(to_line(msg))
        x -> IO.puts(to_line(IO.inspect(x)))
      end

      loop()
    end
  end


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

    @type t :: %__MODULE__{
      outputer: pid(),
    }
    defstruct [outputer: nil]

    def output(%Chopstick{outputer: o}, msg) do
      send(o, {self(), "chopstick #{self()}: #{msg}"})
    end

    def startup(outputer) do
      c_pid = spawn(
        fn ->
          post_startup(%Chopstick{
            outputer: outputer,
          })
        end)
      c_pid
    end

    def post_startup(%Chopstick{} = c) do
      output(c, "started up.")
      not_acquired(c)
    end

    def not_acquired(%Chopstick{} = c) do
      output(c, "ready to be acquired by some lucky philosopher")
      receive do
        {:acquire, acquired_by_pid} ->
          send(acquired_by_pid, {:chopstick_acquired, self()})
          output(c, "acquired by #{acquired_by_pid}")
          acquired(c, acquired_by_pid)
      end
    end

    def acquired(c, acquired_by_pid) do
      output(c, "is now acquired by #{acquired_by_pid}")
      receive do
        {:release, ^acquired_by_pid} ->
          send(acquired_by_pid, {:chopstick_released, self()})
          output(c, "is now released by #{acquired_by_pid}")
          not_acquired(c)
      end
    end
  end #module Chopstick


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

    def output(%Philosopher{id: id, outputer: o}, msg), do: send(o, {self(), "philosopher '#{id}': #{msg}."})

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
        total_rice_eaten: total_rice_eaten} = p) do

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

    def startup(id, l, r, bowl, o) do
      phil_pid = spawn(
        fn -> think(%Philosopher{
          id: id,
          left_chopstick: l,
          right_chopstick: r,
          total_rice_eaten: o,
          bowl_of_rice: bowl,
          outputer: o,
        }) end)
      phil_pid
    end

  end #module Scratch.DinPhil.Philosopher
end #module Scratch.DinPhil
