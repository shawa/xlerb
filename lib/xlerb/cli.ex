defmodule Xlerb.CLI do
  alias Xlerb.Compiler.IO, as: CompilerIO

  def main(), do: main(System.argv())
  def main(args), do: :argparse.run(args, cli(), %{progname: ~c"xlerb"})

  defp cli do
    %{
      arguments: [],
      handler: {__MODULE__, :print_help},
      help: ~c"Xlerb - A stack-based language for Elixir",
      commands: %{
        ~c"repl" => %{
          help: ~c"Run the REPL with compiled modules from lib/",
          arguments: [],
          handler: {__MODULE__, :handle_repl}
        },
        ~c"compile" => %{
          help: ~c"Compile all .xlb files from lib/ to _build/",
          arguments: [],
          handler: {__MODULE__, :handle_compile}
        },
        ~c"run" => %{
          help: ~c"Execute xlerb code as the entrypoint",
          arguments: [
            %{
              name: :code,
              type: :string,
              help: ~c"The xlerb code to execute (e.g., 'module:word' or '1 2 3')"
            }
          ],
          handler: {__MODULE__, :handle_run}
        },
        ~c"format" => %{
          help: ~c"Format all .xlb files in lib/ (currently no-op)",
          arguments: [],
          handler: {__MODULE__, :handle_format}
        }
      }
    }
  end

  def print_help(_args) do
    IO.puts(:argparse.help(cli(), %{progname: ~c"xlerb"}))
  end

  def handle_repl(_args) do
    IO.puts("Compiling modules from lib/...")
    CompilerIO.compile_all_xlb_files("lib")
    CompilerIO.ensure_build_dir_in_code_path()
    IO.puts("\nStarting REPL...\n")
    Xlerb.REPL.run()
  end

  def handle_compile(_args) do
    IO.puts("Compiling all .xlb files...")

    case CompilerIO.compile_all_xlb_files("lib") do
      {:ok, _results} ->
        :ok

      {:error, _errors} ->
        System.halt(1)
    end
  end

  def handle_run(%{code: code}) do
    IO.puts("Compiling modules from lib/...")

    case CompilerIO.compile_all_xlb_files("lib") do
      {:ok, _results} ->
        CompilerIO.ensure_build_dir_in_code_path()
        code_string = List.to_string(code)
        execute_code(code_string)

      {:error, _errors} ->
        System.halt(1)
    end
  end

  def handle_format(_args) do
    xlb_files = CompilerIO.find_xlb_files("lib")

    if Enum.empty?(xlb_files) do
      IO.puts("No .xlb files found in lib/")
    else
      IO.puts("Formatting #{length(xlb_files)} file(s)...")

      Enum.each(xlb_files, fn file ->
        IO.puts("  #{file}")

        case File.read(file) do
          {:ok, content} ->
            File.write!(file, content)

          {:error, reason} ->
            IO.puts("    ERROR: #{:file.format_error(reason)}")
        end
      end)

      IO.puts("\nFormatting complete!")
    end
  end

  defp execute_code(code_string) do
    case Xlerb.string_to_quoted_for_repl(code_string) do
      {:ok, ast} ->
        try do
          stack_var = Macro.var(:stack, nil)

          wrapped_ast =
            quote do
              import Kernel, only: []
              import :"xlerb:kernel"
              unquote(stack_var) = []
              unquote_splicing(ast)
              unquote(stack_var)
            end

          {result, _bindings} = Code.eval_quoted(wrapped_ast)
          IO.inspect(result, label: "Result")
        rescue
          e ->
            IO.puts("Error executing code: #{Exception.message(e)}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("Error compiling code: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
