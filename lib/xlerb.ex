defmodule Xlerb do
  @moduledoc """
  Xlerb - A stack-based language compiler for Elixir.
  """

  alias Xlerb.Compiler

  @doc """
  Compiles a Xlerb string through the entire pipeline:
  1. Lexer - tokenize the source
  2. Parser - build AST
  3. Compiler - convert to Elixir AST
  4. Code.compile_quoted - produce BEAM bytecode

  Returns {:ok, module, binary} on success, {:error, reason} on failure.
  """
  def compile_string(source) do
    with {:ok, elixir_ast} <- string_to_quoted(source),
         compiled <- Code.compile_quoted(elixir_ast) do
      case compiled do
        [{module, binary}] ->
          {:ok, module, binary}

        modules when is_list(modules) ->
          {:ok, modules}
      end
    end
  end

  def string_to_quoted(source) do
    with {:ok, tokens, _} <- source |> to_charlist() |> :xlerb_lexer.string(),
         {:ok, {:program, expressions}} <- :xlerb_parser.parse(tokens),
         elixir_ast <- Enum.map(expressions, &Compiler.compile/1) do
      {:ok, elixir_ast}
    end
  end

  def string_to_quoted_for_repl(source) do
    with {:ok, tokens, _} <- source |> to_charlist() |> :xlerb_lexer.string(),
         {:ok, {:program, expressions}} <- :xlerb_parser.parse(tokens),
         elixir_ast <-
           Enum.map(
             expressions,
             &Compiler.compile(&1, %{var_context: nil, current_module: :"xlerb:repl:context"})
           ) do
      {:ok, elixir_ast}
    end
  end
end
