defmodule Xlerb.REPL.Server do
  use GenServer

  alias Xlerb.REPL.HistoryServer

  defstruct buffer: [],
            history_browse_id: nil,
            stack: []

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    initial_stack = Keyword.get(opts, :stack, [])

    state = %__MODULE__{stack: initial_stack}

    io_write("\r\nXlerb REPL\r\nCtrl+D to exit\r\n\r\n")
    write_prompt(state.stack)

    {:ok, state}
  end

  def dispatch_event(event) do
    GenServer.cast(__MODULE__, {:shell_event, event})
  end

  @impl true
  def handle_cast({:shell_event, event}, state) do
    {:noreply, dispatch_event(state, event)}
  end

  @impl true
  def handle_info({:io_request, from, reply_as, request}, state) do
    reply = handle_io_request(request)
    send(from, {:io_reply, reply_as, reply})
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp dispatch_event(state, :eof), do: dispatch_event(state, :ctrl_d)

  defp dispatch_event(state, :ctrl_d) do
    io_write("\r\nExiting\r\n")
    :erlang.halt(0)
    state
  end

  defp dispatch_event(%__MODULE__{} = state, {:letter, code}) do
    old_buffer = state.buffer
    new_buffer = old_buffer ++ [code]
    new_state = %{state | buffer: new_buffer, history_browse_id: nil}
    render_buffer(new_state, old_buffer)
  end

  defp dispatch_event(%__MODULE__{buffer: []} = state, :backspace), do: state

  defp dispatch_event(%__MODULE__{} = state, :backspace) do
    old_buffer = state.buffer
    new_buffer = :lists.droplast(old_buffer)
    new_state = %{state | buffer: new_buffer, history_browse_id: nil}
    render_buffer(new_state, old_buffer)
  end

  defp dispatch_event(%__MODULE__{} = state, :enter) do
    buffer = state.buffer
    io_write("\r\n")
    execute_buffer(buffer, state)
  end

  defp dispatch_event(%__MODULE__{} = state, {:arrow, :up}) do
    current_max = HistoryServer.index()

    if current_max == 0 do
      # No history entries
      state
    else
      new_id =
        case state.history_browse_id do
          nil -> current_max
          id when id > 1 -> id - 1
          id -> id
        end

      case HistoryServer.get(new_id) do
        nil ->
          state

        entry ->
          new_buffer = String.to_charlist(entry.content)

          %{state | buffer: new_buffer, history_browse_id: new_id}
          |> render_buffer(state.buffer)
      end
    end
  end

  defp dispatch_event(%__MODULE__{} = state, {:arrow, :down}) do
    current_max = HistoryServer.index()

    case state.history_browse_id do
      nil ->
        state

      id when id >= current_max ->
        %{state | buffer: [], history_browse_id: nil}
        |> render_buffer(state.buffer)

      id ->
        new_id = id + 1

        case HistoryServer.get(new_id) do
          nil ->
            %{state | buffer: [], history_browse_id: nil}
            |> render_buffer(state.buffer)

          entry ->
            new_buffer = String.to_charlist(entry.content)

            %{state | buffer: new_buffer, history_browse_id: new_id}
            |> render_buffer(state.buffer)
        end
    end
  end

  defp dispatch_event(state, _event), do: state

  defp execute_buffer(buffer, state) do
    code = :unicode.characters_to_binary(buffer)

    # Persist non-empty commands to history
    if code != "" do
      HistoryServer.insert(code)
      HistoryServer.persist()
    end

    new_stack =
      if code == "" do
        state.stack
      else
        compiled = Xlerb.string_to_quoted_for_repl(code)

        case compiled do
          {:ok, ast} ->
            stack_var = Macro.var(:stack, nil)

            wrapped_ast =
              quote do
                import Kernel, only: []
                import :"xlerb:kernel"
                unquote(stack_var) = unquote(Macro.escape(state.stack))
                unquote_splicing(ast)
              end

            try do
              {_, bindings} = Code.eval_quoted(wrapped_ast)
              Keyword.fetch!(bindings, :stack)
            rescue
              e ->
                io_write("Error: #{inspect(e)}\r\n")
                state.stack
            end

          {:error, error} ->
            io_write("Error: #{error}\r\n")
            state.stack
        end
      end

    write_prompt(new_stack)

    %{
      state
      | buffer: [],
        history_browse_id: nil,
        stack: new_stack
    }
  end

  defp write_prompt(stack) do
    io_write("xlerb[#{length(stack)}]> ")
  end

  defp clear_line_with_prompt(buffer, stack) do
    prompt_text = "xlerb[#{length(stack)}]> "
    prompt_len = String.length(prompt_text)
    total_len = prompt_len + length(buffer)

    backspaces = :lists.duplicate(total_len, ?\b)
    spaces = :lists.duplicate(total_len, ?\s)

    io_write([backspaces, spaces, backspaces])
  end

  defp render_buffer(%__MODULE__{} = state, old_buffer) do
    clear_line_with_prompt(old_buffer, state.stack)
    write_prompt(state.stack)
    io_write(state.buffer)
    state
  end

  defp io_write(data) do
    processed =
      data
      |> :unicode.characters_to_list()
      |> fix_newlines()

    IO.binwrite(:stdio, processed)
  end

  defp fix_newlines(chars), do: fix_newlines(chars, [], false)

  defp fix_newlines([], acc, _prev_cr), do: :lists.reverse(acc)

  defp fix_newlines([?\r | rest], acc, _prev_cr), do: fix_newlines(rest, [?\r | acc], true)

  defp fix_newlines([?\n | rest], acc, prev_cr) do
    acc = if prev_cr, do: acc, else: [?\r | acc]
    fix_newlines(rest, [?\n | acc], false)
  end

  defp fix_newlines([char | rest], acc, _prev_cr), do: fix_newlines(rest, [char | acc], false)

  defp handle_io_request({:requests, requests}) when is_list(requests) do
    Enum.reduce_while(requests, :ok, fn req, _acc ->
      case handle_io_request(req) do
        :ok -> {:cont, :ok}
        other -> {:halt, other}
      end
    end)
  end

  defp handle_io_request({:put_chars, chars}) do
    handle_io_request({:put_chars, :unicode, chars})
  end

  defp handle_io_request({:put_chars, encoding, chars}) do
    chars_list =
      case encoding do
        :unicode -> :unicode.characters_to_list(chars)
        :latin1 -> :erlang.binary_to_list(:erlang.iolist_to_binary(chars))
        _ -> :unicode.characters_to_list(chars)
      end

    io_write(chars_list)
    :ok
  end

  defp handle_io_request({:put_chars, encoding, module, function, args}) do
    chars = apply(module, function, args)
    handle_io_request({:put_chars, encoding, chars})
  end

  defp handle_io_request({:setopts, _opts}), do: :ok
  defp handle_io_request(:getopts), do: {:ok, [binary: true, encoding: :unicode]}
  defp handle_io_request({:get_until, _encoding, _prompt, _m, _f, _a}), do: {:error, :enotsup}
  defp handle_io_request({:get_chars, _encoding, _prompt, _count}), do: {:error, :enotsup}
  defp handle_io_request({:get_line, _encoding, _prompt}), do: {:error, :enotsup}
  defp handle_io_request(_request), do: {:error, :request}
end
