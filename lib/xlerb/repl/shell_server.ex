defmodule Xlerb.REPL.ShellServer do
  use GenServer

  defstruct repl_server: nil, partial: []

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def recv_chr(server, chr) do
    GenServer.cast(server, {:recv_chr, chr})
  end

  @impl true
  def init(opts) do
    repl_server = Keyword.fetch!(opts, :repl_server)
    {:ok, %__MODULE__{repl_server: repl_server, partial: []}}
  end

  @impl true
  def handle_cast({:recv_chr, chr}, state) do
    {:noreply, process_input(state, chr)}
  end

  defp process_input(state, :eof), do: forward_event(state, :eof)

  defp process_input(state, data) when is_integer(data), do: process_code(state, data)

  defp process_input(state, data) do
    data
    |> :unicode.characters_to_list()
    |> Enum.reduce(state, fn codepoint, acc_state ->
      process_code(acc_state, codepoint)
    end)
  end

  defp process_code(%__MODULE__{partial: []} = state, ?\e) do
    %{state | partial: [?\e]}
  end

  defp process_code(%__MODULE__{partial: [?\e]} = state, ?[) do
    %{state | partial: [?\e, ?[]}
  end

  defp process_code(%__MODULE__{partial: [?\e]} = state, codepoint) do
    state
    |> forward_event(:escape)
    |> Map.put(:partial, [])
    |> process_code(codepoint)
  end

  defp process_code(%__MODULE__{partial: [?\e, ?[]} = state, codepoint) do
    seq = [?\e, ?[, codepoint]

    event =
      case seq do
        [?\e, ?[, ?A] -> {:arrow, :up}
        [?\e, ?[, ?B] -> {:arrow, :down}
        [?\e, ?[, ?C] -> {:arrow, :right}
        [?\e, ?[, ?D] -> {:arrow, :left}
        _ -> {:control_sequence, :unicode.characters_to_binary(seq)}
      end

    state
    |> Map.put(:partial, [])
    |> forward_event(event)
  end

  defp process_code(state, ?\r), do: forward_event(state, :enter)
  defp process_code(state, ?\n), do: forward_event(state, :enter)
  defp process_code(state, 127), do: forward_event(state, :backspace)
  defp process_code(state, 4), do: forward_event(state, :ctrl_d)

  defp process_code(state, codepoint) when codepoint in 32..126 do
    forward_event(state, {:letter, codepoint})
  end

  defp process_code(state, codepoint) do
    forward_event(state, {:letter, codepoint})
  end

  defp forward_event(state, event) do
    GenServer.cast(state.repl_server, {:shell_event, event})
    state
  end
end
