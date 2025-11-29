defmodule Xlerb.Compiler.IO do
  @build_dir "_build/dev/lib/xlerb/ebin"

  def compile_file(xlb_path) do
    case File.read(xlb_path) do
      {:ok, source} ->
        compile_source(source, xlb_path)

      {:error, reason} ->
        {:error, {:file_read, xlb_path, reason}}
    end
  end

  def compile_source(source, source_path) do
    case Xlerb.compile_string(source) do
      {:ok, module, binary} ->
        write_beam(module, binary, source_path)

      {:ok, modules} when is_list(modules) ->
        results =
          Enum.map(modules, fn {module, binary} ->
            write_beam(module, binary, source_path)
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, {:compile, source_path, reason}}
    end
  end

  def write_beam(module, binary, source_path) do
    beam_path = beam_path_for_module(module)
    File.mkdir_p!(Path.dirname(beam_path))

    case File.write(beam_path, binary) do
      :ok ->
        {:ok, {module, beam_path}}

      {:error, reason} ->
        {:error, {:write_beam, source_path, beam_path, reason}}
    end
  end

  def beam_path_for_module(module) do
    module_name = Atom.to_string(module)
    Path.join(@build_dir, "#{module_name}.beam")
  end

  def find_xlb_files(dir \\ "lib") do
    case File.exists?(dir) do
      true ->
        dir
        |> Path.join("**/*.xlb")
        |> Path.wildcard()
        |> Enum.sort()

      false ->
        []
    end
  end

  def compile_all_xlb_files(dir \\ "lib") do
    xlb_files = find_xlb_files(dir)

    if Enum.empty?(xlb_files) do
      IO.puts("No .xlb files found in #{dir}/")
      {:ok, []}
    else
      results =
        Enum.map(xlb_files, fn file ->
          IO.puts("Compiling #{file}...")

          case compile_file(file) do
            {:ok, {module, beam_path}} ->
              IO.puts("  -> #{beam_path}")
              {:ok, {file, module, beam_path}}

            {:ok, modules} when is_list(modules) ->
              Enum.each(modules, fn {:ok, {_module, beam_path}} ->
                IO.puts("  -> #{beam_path}")
              end)

              {:ok, {file, modules}}

            {:error, reason} ->
              IO.puts("  ERROR: #{format_error(reason)}")
              {:error, {file, reason}}
          end
        end)

      errors = Enum.filter(results, &match?({:error, _}, &1))

      if Enum.empty?(errors) do
        IO.puts("\nCompilation successful!")
        {:ok, results}
      else
        IO.puts("\nCompilation completed with errors.")
        {:error, errors}
      end
    end
  end

  def ensure_build_dir_in_code_path do
    unless @build_dir in :code.get_path() do
      :code.add_path(String.to_charlist(@build_dir))
    end
  end

  def format_error({:file_read, path, reason}) do
    "Failed to read #{path}: #{:file.format_error(reason)}"
  end

  def format_error({:compile, path, reason}) do
    "Failed to compile #{path}: #{inspect(reason)}"
  end

  def format_error({:write_beam, source_path, beam_path, reason}) do
    "Failed to write #{beam_path} (from #{source_path}): #{:file.format_error(reason)}"
  end

  def format_error(reason) do
    inspect(reason)
  end
end
