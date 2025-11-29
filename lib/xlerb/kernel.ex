defmodule :"xlerb:kernel" do
  import Kernel, except: [send: 2, self: 0, spawn: 0, inspect: 1]
  alias Xlerb.Compiler

  # this just needs to be something you're not going to accidentally push onto the stack
  @message_marker {:__XLERB_MESSAGE_MARKER__, :"40fd3ad0-c1c1-11f0-bb26-ef13bcc8eb8a"}

  for op <- ~w[* + - /]a do
    def unquote(op)([h, h2 | t]) do
      [
        # order here matters - non-commutative need operators are reversed
        Kernel.unquote(op)(h2, h) | t
      ]
    end
  end

  def unquote(:".s")(stack) do
    stack
    |> Enum.with_index()
    |> Enum.each(fn {x, idx} ->
      if idx == 0 do
        IO.write(["  > ", do_inspect(x), "\r\n"])
      else
        IO.write(["    ", do_inspect(x), "\r\n"])
      end
    end)

    stack
  end

  def unquote(:.)([h | t]) do
    IO.write(["    ", do_inspect(h), "\r\n"])
    t
  end

  def unquote(:...)(stack), do: stack
  def dup([h | t]), do: [h, h | t]
  def drop([_ | t]), do: t

  def swap([h, h2 | t]), do: [h2, h | t]
  def rot([h, h2, h3 | t]), do: [h3, h, h2 | t]

  def i([{:quotation, meta, body} = quotation | t]) do
    defining_module = Keyword.get(meta, :defined_in)
    # Store the current quotation for recurse to access
    prev_quotation = Process.get(:xlerb_current_quotation)
    Process.put(:xlerb_current_quotation, quotation)

    try do
      make_fun(body, defining_module).(t)
    after
      # Restore previous quotation (for nested calls)
      if prev_quotation do
        Process.put(:xlerb_current_quotation, prev_quotation)
      else
        Process.delete(:xlerb_current_quotation)
      end
    end
  end

  def recurse(stack) do
    case Process.get(:xlerb_current_quotation) do
      nil ->
        raise "recurse called outside of a quotation"

      quotation ->
        i([quotation | stack])
    end
  end

  def spawn([{:quotation, meta, body} | t]) do
    defining_module = Keyword.get(meta, :defined_in)

    pid =
      Kernel.spawn(fn ->
        make_fun(body, defining_module).(t)
      end)

    [pid | t]
  end

  def write([h | t]) do
    IO.write(h)
    t
  end

  def writeln(stack) do
    new_stack =
      stack
      |> write()

    IO.write("\r\n")
    new_stack
  end

  def inspect([{:quotation, _meta, body} | t]) do
    body_str = body |> Enum.map(&format_ast_element/1) |> Enum.join(" ")
    ["[ #{body_str} ]" | t]
  end

  def inspect([h | t]), do: [do_inspect(h) | t]

  def self(stack), do: [Kernel.self() | stack]

  # Push a quotation that receives any message and pushes it onto the stack
  # Equivalent to [: -> ;] receive
  def whatever(stack) do
    quotation = {:quotation, [defined_in: :"xlerb:kernel"], [{:def, :->, [], []}]}
    [quotation | stack]
  end

  # Flush all messages from the mailbox, discarding them
  def flush(stack) do
    do_flush()
    stack
  end

  defp do_flush do
    receive do
      _ -> do_flush()
    after
      0 -> :ok
    end
  end

  # ! is a bit different from what you might expect from Erlang
  # The point is to use it in an expression like:
  #
  #    `pid ! x1 x2 ... xn send`
  #
  # `!` pushes a message marker ref onto the stack.
  # `send` then unwinds the stack until it sees the message marker, and sends
  # the collected terms as a list to the preceeding `PID`.
  def unquote(:!)(stack) do
    [@message_marker | stack]
  end

  def send(stack), do: do_send(stack, [])

  def erlang([{:quotation, _meta, body} | t]) do
    case body do
      [word: module, word: function, integer: arity] ->
        {args, rest} = Enum.split(t, arity)
        args_list = Enum.reverse(args)
        result = apply(module, function, args_list)
        [result | rest]

      _ ->
        raise "erlang expects a quotation with [module function arity], got: #{Kernel.inspect(body)}"
    end
  end

  def elixir([{:quotation, _meta, body} | t]) do
    case body do
      [word: module, word: function, integer: arity] ->
        elixir_module = Module.concat([Elixir, module])
        {args, rest} = Enum.split(t, arity)
        args_list = Enum.reverse(args)
        result = apply(elixir_module, function, args_list)
        [result | rest]

      _ ->
        raise "elixir expects a quotation with [Module function arity], got: #{Kernel.inspect(body)}"
    end
  end

  defp do_send([@message_marker, pid | t], acc) when is_pid(pid) do
    Kernel.send(pid, acc)
    t
  end

  defp do_send([h | t], acc), do: do_send(t, [h | acc])
  defp do_send([], _acc), do: raise("Send reached end of stack without message marker")

  defp make_fun(body, defining_module) do
    # Use a neutral env to avoid circular import issues
    env = %{__ENV__ | module: nil, function: nil}

    {fun, []} =
      body
      |> Compiler.compile_quotation_body(defining_module)
      |> Code.eval_quoted([], env)

    fun
  end

  def pack([{:capture, ast} | t]) do
    capture_vars = find_capture_vars(ast)
    max_var = if capture_vars == [], do: 0, else: Enum.max(capture_vars)

    {values, rest} = Enum.split(t, max_var)

    bindings =
      values
      |> Enum.with_index(1)
      |> Enum.map(fn {val, idx} -> {:"&#{idx}", val} end)

    substituted_ast = substitute_captures(ast, bindings)

    {result, []} = Code.eval_quoted(substituted_ast, [])

    [result | rest]
  end

  def unpack([{:capture, ast} | t]) do
    [value | rest] = t

    capture_vars = find_capture_vars(ast)
    max_var = if capture_vars == [], do: 0, else: Enum.max(capture_vars)

    var_asts =
      1..max_var
      |> Enum.map(fn n -> Macro.var(:"var#{n}", __MODULE__) end)

    pattern_ast = substitute_captures_for_pattern(ast, var_asts)

    case_ast =
      quote do
        case unquote(Macro.escape(value)) do
          unquote(pattern_ast) -> {:ok, {unquote_splicing(var_asts)}}
          _ -> :error
        end
      end

    case Code.eval_quoted(case_ast, []) do
      {{:ok, tuple}, _bindings} ->
        extracted_values = Tuple.to_list(tuple)
        extracted_values ++ rest

      {:error, _} ->
        raise MatchError, term: value
    end
  end

  def rev([h | t]) when is_list(h) do
    [Enum.reverse(h) | t]
  end

  def rev([{:quotation, meta, body} | t]) do
    [
      {:quotation, meta, Enum.reverse(body)} | t
    ]
  end

  def unquote(:do)([quotation, quotation_stack | t]) do
    {:quotation, meta, body} = quotation_stack
    new_body = i([quotation | body])
    [{:quotation, meta, new_body} | t]
  end

  defp find_capture_vars(ast) do
    {_, vars} =
      Macro.prewalk(ast, [], fn
        {:&, _, [n]}, acc when is_integer(n) -> {{:&, [], [n]}, [n | acc]}
        node, acc -> {node, acc}
      end)

    vars |> Enum.uniq() |> Enum.sort()
  end

  defp substitute_captures(ast, bindings) do
    Macro.prewalk(ast, fn
      {:&, _, [n]} = node ->
        if is_integer(n) do
          case List.keyfind(bindings, :"&#{n}", 0) do
            {_, value} -> Macro.escape(value)
            nil -> raise "Unbound capture variable: &#{n}"
          end
        else
          node
        end

      node ->
        node
    end)
  end

  defp substitute_captures_for_pattern(ast, var_bindings) do
    Macro.prewalk(ast, fn
      {:&, _, [n]} = node ->
        if is_integer(n) do
          Enum.at(var_bindings, n - 1)
        else
          node
        end

      node ->
        node
    end)
  end

  defp do_inspect(@message_marker), do: "!"
  defp do_inspect({:capture, ast}), do: "&" <> ast_to_capture_string(ast)
  defp do_inspect(h), do: Kernel.inspect(h)

  defp format_ast_element({:integer, value}), do: Kernel.inspect(value)
  defp format_ast_element({:float, value}), do: Kernel.inspect(value)
  defp format_ast_element({:word, word}), do: Atom.to_string(word)

  defp format_ast_element({:quotation, content}),
    do: "[ #{Enum.map(content, &format_ast_element/1) |> Enum.join(" ")} ]"

  defp format_ast_element(other), do: Kernel.inspect(other)

  defp ast_to_capture_string({:&, _, [n]}) when is_integer(n), do: "&#{n}"

  defp ast_to_capture_string({left, right}) do
    "{#{ast_to_capture_string(left)}, #{ast_to_capture_string(right)}}"
  end

  defp ast_to_capture_string({:{}, _, elements}) do
    "{#{elements |> Enum.map(&ast_to_capture_string/1) |> Enum.join(", ")}}"
  end

  defp ast_to_capture_string(list) when is_list(list) do
    "[#{list |> Enum.map(&ast_to_capture_string/1) |> Enum.join(", ")}]"
  end

  defp ast_to_capture_string(%{} = map) do
    entries =
      map
      |> Enum.map(fn {k, v} -> "#{ast_to_capture_string(k)} => #{ast_to_capture_string(v)}" end)
      |> Enum.join(", ")

    "%{#{entries}}"
  end

  defp ast_to_capture_string({:%{}, _, pairs}) do
    entries =
      pairs
      |> Enum.map(fn {k, v} -> "#{ast_to_capture_string(k)} => #{ast_to_capture_string(v)}" end)
      |> Enum.join(", ")

    "%{#{entries}}"
  end

  defp ast_to_capture_string(atom) when is_atom(atom), do: ":#{atom}"
  defp ast_to_capture_string(str) when is_binary(str), do: Kernel.inspect(str)
  defp ast_to_capture_string(num) when is_number(num), do: Kernel.inspect(num)
  defp ast_to_capture_string(other), do: Kernel.inspect(other)
end
