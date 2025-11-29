defmodule Xlerb.Compiler do
  def compile(ast, ctx \\ %{})

  def compile({:defmodule, name, _pattern, body}, ctx) do
    xlerb_qualified_name = :"xlerb:#{name}"

    module_ctx =
      ctx
      |> Map.put(:current_module, xlerb_qualified_name)
      # I went through hell and back trying to get this implicit 'stack'
      # variable to work.
      #
      # There are 3 cases, and if you fix one you're liable to break the other 2:
      #
      # - calling a bare fragment in the REPL (the REPL's `stack`)
      # - defining a word in a module (the `Xlerb.Compiler` stack)
      # - defining a word in a module IN THE REPL (wtf stack is this?!?)
      #
      # By default, if you use a variable in a quote, you'll get a variable
      # tuple whose 'context' is the module the quote appears in.
      # This is part of the hygiene system Elixir uses.
      #
      # Now in the REPL, we want to thread our own stack variable through the calls.
      # Code.eval_quoted/2's second argument is a bindings keyword list, but if the
      # variables are already defined with a 'context' this bindings list is ignored.
      |> Map.put(:var_context, __MODULE__)

    definitions =
      body
      |> List.first()
      |> case do
        {:quotation, content} -> content
        _ -> []
      end
      |> Enum.map(&compile(&1, module_ctx))

    quote do
      defmodule unquote(xlerb_qualified_name) do
        # Don't want the Elixir kernel
        import Kernel, only: []
        # ...only our kernel :)
        import :"xlerb:kernel"

        unquote_splicing(definitions)
      end
    end
  end

  def compile({:def, word, pattern, body}, ctx) do
    body_ast = Enum.map(body, &compile(&1, ctx))
    var_context = Map.get(ctx, :var_context, __MODULE__)
    pattern_ast = build_pattern_ast(pattern, var_context)

    if pattern == [] do
      quote do
        def unquote(word)(stack \\ [])

        def unquote(word)(stack) do
          unquote_splicing(body_ast)
          stack
        end
      end
    else
      quote do
        def unquote(word)(unquote(pattern_ast) = stack) do
          unquote_splicing(body_ast)
          stack
        end
      end
    end
  end

  def compile({:defp, word, pattern, body}, ctx) do
    body_ast = Enum.map(body, &compile(&1, ctx))
    var_context = Map.get(ctx, :var_context, __MODULE__)
    pattern_ast = build_pattern_ast(pattern, var_context)

    if pattern == [] do
      quote do
        defp unquote(word)(stack) do
          unquote_splicing(body_ast)
          stack
        end
      end
    else
      quote do
        defp unquote(word)(unquote(pattern_ast) = stack) do
          unquote_splicing(body_ast)
          stack
        end
      end
    end
  end

  def compile({:integer, value}, ctx) do
    stack_var = Macro.var(:stack, Map.get(ctx, :var_context, __MODULE__))

    quote do
      unquote(stack_var) = [unquote(value) | unquote(stack_var)]
    end
  end

  def compile({:float, value}, ctx) do
    stack_var = Macro.var(:stack, Map.get(ctx, :var_context, __MODULE__))

    quote do
      unquote(stack_var) = [unquote(value) | unquote(stack_var)]
    end
  end

  def compile({:atom, value}, ctx) do
    stack_var = Macro.var(:stack, Map.get(ctx, :var_context, __MODULE__))

    quote do
      unquote(stack_var) = [unquote(value) | unquote(stack_var)]
    end
  end

  def compile({:string, value}, ctx) do
    stack_var = Macro.var(:stack, Map.get(ctx, :var_context, __MODULE__))

    quote do
      unquote(stack_var) = [unquote(value) | unquote(stack_var)]
    end
  end

  def compile({:word, word}, ctx) do
    stack_var = Macro.var(:stack, Map.get(ctx, :var_context, __MODULE__))

    case extract_call(word) do
      word when is_atom(word) ->
        quote do
          unquote(stack_var) = unquote(word)(unquote(stack_var))
        end

      {prefix, word} ->
        quote do
          unquote(stack_var) = unquote(prefix).unquote(word)(unquote(stack_var))
        end
    end
  end

  def compile({:case, quotation_content}, ctx) do
    for branch <- quotation_content do
      if match?({:defp, :->, _pattern, _body}, branch) do
        raise "Branches of case statements cannot be private!"
      end
    end

    arrow_definitions = Enum.filter(quotation_content, &match?({:def, :->, _pattern, _body}, &1))

    var_context = Map.get(ctx, :var_context, __MODULE__)
    stack_var = Macro.var(:stack, var_context)

    clause_asts =
      arrow_definitions
      |> Enum.map(fn {:def, :->, pattern, body} ->
        pattern_ast = build_pattern_ast(pattern, var_context)
        body_ast = Enum.map(body, &compile(&1, ctx))

        body_block =
          quote do
            unquote_splicing(body_ast)
            unquote(stack_var)
          end

        {:->, [], [[pattern_ast], body_block]}
      end)

    case_ast =
      {:case, [],
       [
         stack_var,
         [do: clause_asts]
       ]}

    quote do
      unquote(stack_var) = unquote(case_ast)
    end
  end

  def compile({:receive, quotation_content}, ctx) do
    for branch <- quotation_content do
      if match?({:defp, :->, _pattern, _body}, branch) do
        raise "Branches of receive statements cannot be private!"
      end
    end

    arrow_definitions = Enum.filter(quotation_content, &match?({:def, :->, _pattern, _body}, &1))

    var_context = Map.get(ctx, :var_context, __MODULE__)
    stack_var = Macro.var(:stack, var_context)

    clause_asts =
      arrow_definitions
      |> Enum.map(fn {:def, :->, pattern, body} ->
        pattern_ast = build_pattern_ast(pattern, var_context)
        body_ast = Enum.map(body, &compile(&1, ctx))

        message_pattern = quote do: message = unquote(pattern_ast)

        body_block =
          quote do
            unquote(stack_var) = message ++ unquote(stack_var)
            unquote_splicing(body_ast)
            unquote(stack_var)
          end

        {:->, [], [[message_pattern], body_block]}
      end)

    receive_ast = {:receive, [], [[do: clause_asts]]}

    quote do
      unquote(stack_var) = unquote(receive_ast)
    end
  end

  def compile({:quotation, content}, ctx) do
    stack_var = Macro.var(:stack, Map.get(ctx, :var_context, __MODULE__))

    # Escape the content to prevent it from being interpreted as code
    escaped_content = Macro.escape(content)
    quotation_tuple = {:{}, [], [:quotation, [defined_in: ctx.current_module], escaped_content]}

    quote do
      unquote(stack_var) = [
        unquote(quotation_tuple)
        | unquote(stack_var)
      ]
    end
  end

  def compile({:capture, tokens}, ctx) do
    stack_var = Macro.var(:stack, Map.get(ctx, :var_context, __MODULE__))

    capture_string = tokens_to_string(tokens)
    capture_ast = Code.string_to_quoted!(capture_string)
    escaped_ast = Macro.escape(capture_ast)

    capture_tuple = {:{}, [], [:capture, escaped_ast]}

    quote do
      unquote(stack_var) = [
        unquote(capture_tuple)
        | unquote(stack_var)
      ]
    end
  end

  def compile_quotation_body(content, defining_module) do
    # Use nil context so the stack variable matches the fn parameter
    ast =
      Enum.map(content, &compile(&1, %{current_module: defining_module, var_context: nil}))

    stack_var = Macro.var(:stack, nil)

    if defining_module == :"xlerb:repl:context" do
      quote do
        fn unquote(stack_var) ->
          import Kernel, only: []
          import :"xlerb:kernel"
          unquote_splicing(ast)
          unquote(stack_var)
        end
      end
    else
      quote do
        fn unquote(stack_var) ->
          import Kernel, only: []
          import :"xlerb:kernel"
          import unquote(defining_module)
          unquote_splicing(ast)
          unquote(stack_var)
        end
      end
    end
  end

  defp build_pattern_ast([], var_context) do
    Macro.var(:stack, var_context)
  end

  defp build_pattern_ast(pattern, _var_context) do
    tail_var = quote do: _t

    pattern
    |> Enum.reduce(tail_var, fn
      :_, acc ->
        quote do: [_ | unquote(acc)]

      value, acc ->
        quote do: [unquote(value) | unquote(acc)]
    end)
  end

  defp extract_call(word) do
    word_str = Atom.to_string(word)

    case String.split(word_str, ":") do
      [single_word] ->
        String.to_atom(single_word)

      parts when length(parts) > 1 ->
        {module_parts, [word_part]} = Enum.split(parts, -1)
        module = :"xlerb:#{Enum.join(module_parts, ":")}"
        {module, String.to_atom(word_part)}
    end
  end

  defp tokens_to_string(tokens) do
    strings = Enum.map(tokens, &token_to_string/1)

    result =
      strings
      |> Enum.reduce([], fn
        str, [] -> [str]
        str, [last | rest] -> [str, needs_space?(last, str), last | rest]
      end)
      |> Enum.reverse()
      |> Enum.join("")

    result
  end

  defp needs_space?(_, "{"), do: ""
  defp needs_space?(_, "}"), do: ""
  defp needs_space?(_, "["), do: ""
  defp needs_space?(_, "]"), do: ""
  defp needs_space?(_, ","), do: ""
  defp needs_space?(_, "|"), do: ""
  defp needs_space?("{", _), do: ""
  defp needs_space?("}", _), do: ""
  defp needs_space?("[", _), do: ""
  defp needs_space?("]", _), do: ""
  defp needs_space?(",", _), do: " "
  defp needs_space?("|", _), do: " "
  defp needs_space?("%", _), do: ""
  defp needs_space?("=>", _), do: " "
  defp needs_space?(_, "=>"), do: " "
  defp needs_space?(_, _), do: " "

  defp token_to_string({:"{", _}), do: "{"
  defp token_to_string({:"}", _}), do: "}"
  defp token_to_string({:"[", _}), do: "["
  defp token_to_string({:"]", _}), do: "]"
  defp token_to_string({:",", _}), do: ","
  defp token_to_string({:|, _}), do: "|"
  defp token_to_string({:%, _}), do: "%"
  defp token_to_string({:"=>", _}), do: "=>"
  defp token_to_string({:capture_var, _, n}), do: "&#{n}"
  defp token_to_string({:atom, _, a}), do: ":#{a}"
  defp token_to_string({:atom_key, _, a}), do: "#{a}:"
  defp token_to_string({:string, _, s}), do: inspect(s)
  defp token_to_string({:integer, _, i}), do: Integer.to_string(i)
  defp token_to_string({:float, _, f}), do: Float.to_string(f)
  defp token_to_string({:word, _, w}), do: Atom.to_string(w)
end
