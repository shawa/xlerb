defmodule Xlerb.XlerbTest do
  use ExUnit.Case

  setup ctx do
    {:ok, ast} = Xlerb.string_to_quoted(ctx.code)

    {module, modules_to_cleanup} =
      case Xlerb.compile_string(ctx.code) do
        {:ok, module, binary} ->
          :code.load_binary(module, ~c"#{module}.beam", binary)
          {module, [module]}

        {:ok, modules} ->
          for {mod, binary} <- modules do
            :code.load_binary(mod, ~c"#{mod}.beam", binary)
          end

          {elem(List.last(modules), 0), Enum.map(modules, &elem(&1, 0))}
      end

    on_exit(fn ->
      for mod <- modules_to_cleanup do
        :code.purge(mod)
        :code.delete(mod)
      end
    end)

    %{module: module, ast: ast, elixir_code: Macro.to_string(ast)}
  end

  describe "compile/1" do
    @tag code: """
         : Test [
           : public dup priv;
           : priv drop; private
         ] ; module
         """
    test "compiles a module", ctx do
      # expect the stack-taking variant, and the default-empty variant to be
      # exported
      assert function_exported?(ctx.module, :public, 1)
      assert function_exported?(ctx.module, :public, 0)

      refute function_exported?(ctx.module, :priv, 1)
      refute function_exported?(ctx.module, :priv, 0)
    end

    @tag code: """
         : stack-test [
           : push-numbers 1 2 3 ;
           : add + ;
           : do-dup dup dup drop ;
         ] ; module
         """
    test "stack interactions", ctx do
      assert ctx.module."push-numbers"() == [3, 2, 1]
      assert ctx.module."do-dup"([1]) == [1, 1]
      assert ctx.module.add([1, 2]) == [3]
    end
  end

  describe "pattern matching" do
    @tag code: """
         : pattern-test [
            : 1 add-two-to-one 2 + ;
         ] ; module
         """
    test "basic matching", ctx do
      refute function_exported?(ctx.module, :"add-two-to-one", 0)

      assert ctx.module."add-two-to-one"([1]) == [3]

      assert_raise FunctionClauseError, fn ->
        ctx.module."add-two-to-one"([0])
      end
    end

    @tag code: """
         : underscore-test [
            : _ignored test drop 1 ;
         ] ; module
         """
    test "underscore prefix for ignored patterns", ctx do
      assert ctx.module.test([5]) == [1]
      assert ctx.module.test([10]) == [1]
    end

    @tag code: """
         : pattern-test [
            : 1 3 five-now 5;
         ] ; module
         """
    test "matching on multiple values", ctx do
      assert ctx.module."five-now"([3, 1]) == [5, 3, 1]
    end

    @tag code: """
         : factorial-test [
           : 0 factorial drop 1;
           : _ factorial dup 1 - factorial * ;
         ] ; module
         """

    test "factorial", ctx do
      assert ctx.module.factorial([0]) == [1]
      assert ctx.module.factorial([5]) == [120]
    end
  end

  describe "case statements" do
    @tag code: """
         : case-test [
           : test-case [ : 0 -> 0 ; ] case ;
         ] ; module
         """
    test "basic case statement", ctx do
      assert ctx.module."test-case"([0]) == [0, 0]
    end

    @tag code: """
         : case-test [
           : test-case [ : 0 -> 0 ; : 10 -> 100 ; : _ -> 50 ; ] case ;
         ] ; module
         """
    test "case statement with multiple arms", ctx do
      assert ctx.module."test-case"([0]) == [0, 0]
      assert ctx.module."test-case"([10]) == [100, 10]
      assert ctx.module."test-case"([5]) == [50, 5]
    end

    @tag code: """
         : case-test [
           : test-case [ : 10 -> drop 100 ; ] case ;
         ] ; module
         """
    test "case statement with expressions in arm", ctx do
      assert ctx.module."test-case"([10]) == [100]
    end

    @tag code: """
         : case-test [
           : test-case [ : 0 -> 0 ; : _ -> drop 50 ; ] case ;
         ] ; module
         """
    test "case statement with wildcard pattern", ctx do
      assert ctx.module."test-case"([0]) == [0, 0]
      assert ctx.module."test-case"([5]) == [50]
    end
  end

  describe "snake_case words" do
    @tag code: """
         : snake-case-test [
           : double_value 2 * ;
           : add_three 3 + ;
         ] ; module
         """
    test "allows underscores in word names", ctx do
      assert ctx.module.double_value([5]) == [10]
      assert ctx.module.add_three([7]) == [10]
    end

    @tag code: """
         : combined-test [
           : 1 _ignored_value transform_data 100 ;
         ] ; module
         """
    test "combines underscore patterns with snake_case names", ctx do
      assert ctx.module.transform_data([999, 1]) == [100, 999, 1]
      assert ctx.module.transform_data([777, 1]) == [100, 777, 1]
    end
  end

  describe "erlang and elixir interop" do
    @tag code: """
         : erlang-test [
           : test-erlang-0 [ erlang unique_integer 0 ] erlang ;
           : test-erlang-2 [ erlang + 2 ] erlang ;
         ] ; module
         """
    test "calls erlang functions", ctx do
      result = ctx.module."test-erlang-0"([])
      assert is_integer(hd(result))

      assert ctx.module."test-erlang-2"([5, 10]) == [15]
    end

    @tag code: """
         : elixir-test [
           : test-elixir-1 [ Enum count 1 ] elixir ;
         ] ; module
         """
    test "calls elixir functions", ctx do
      assert ctx.module."test-elixir-1"([[1, 2, 3]]) == [3]
    end
  end

  describe "module-qualified function calls" do
    @tag code: """
         : helper [
           : triple 3 * ;
         ] ; module

         : call-test [
           : test-call helper:triple ;
         ] ; module
         """
    test "calls function from another module", ctx do
      assert ctx.module."test-call"([5]) == [15]
    end

    @tag code: """
         : math:helpers [
           : double 2 * ;
         ] ; module

         : use-math [
           : use-double math:helpers:double ;
         ] ; module
         """
    test "calls function from nested module", ctx do
      assert ctx.module."use-double"([7]) == [14]
    end
  end

  describe "receive statements" do
    @tag code: """
         : receive-test [
           : test-receive [ : 0 -> 0 ; ] receive ;
         ] ; module
         """
    test "basic receive statement", ctx do
      pid = self()
      send(pid, [0])
      assert ctx.module."test-receive"([]) == [0, 0]
    end

    @tag code: """
         : receive-test [
           : test-receive
            [
              : 0 -> 99 ;
              : 10 -> 100 ;
              : _ -> ;
            ]
            receive ;
         ] ; module
         """
    test "receive statement with multiple arms", ctx do
      pid = self()
      send(pid, [0])
      assert ctx.module."test-receive"([]) == [99, 0]

      send(pid, [10])
      assert ctx.module."test-receive"([]) == [100, 10]

      ref = make_ref()
      send(pid, [ref])
      assert ctx.module."test-receive"([]) == [ref]
    end

    @tag code: """
         : receive-test [
           : test-receive [ : 10 -> drop 100 ; ] receive ;
         ] ; module
         """
    test "receive statement with expressions in arm", ctx do
      pid = self()
      send(pid, [10])
      assert ctx.module."test-receive"([]) == [100]
    end

    @tag code: """
         : receive-test [
           : test-receive [ : 300 200 -> dup ; ] receive ;
         ] ; module
         """
    test "receive statement spreads message then executes body", ctx do
      pid = self()
      send(pid, [200, 300])
      assert ctx.module."test-receive"([]) == [200, 200, 300]
    end
  end

  describe "atom and string literals" do
    @tag code: """
         : literals-test [
           : push-atom :hello ;
           : push-string "world" ;
           : push-both :foo "bar" ;
         ] ; module
         """
    test "atoms and strings are pushed onto stack", ctx do
      assert ctx.module."push-atom"([]) == [:hello]
      assert ctx.module."push-string"([]) == ["world"]
      assert ctx.module."push-both"([]) == ["bar", :foo]
    end

    @tag code: """
         : string-test [
           : push-string-with-escape "hello\\nworld" ;
         ] ; module
         """
    test "strings with escape sequences", ctx do
      assert ctx.module."push-string-with-escape"([]) == ["hello\nworld"]
    end
  end

  describe "floats" do
    @tag code: """
         : float-test [
           : push-float 3.14 ;
           : push-negative-float -0.001 ;
           : push-scientific 1e10 ;
           : push-scientific-decimal 2.5e-3 ;
         ] ; module
         """
    test "floats are pushed onto stack", ctx do
      assert ctx.module."push-float"([]) == [3.14]
      assert ctx.module."push-negative-float"([]) == [-0.001]
      assert ctx.module."push-scientific"([]) == [1.0e10]
      assert ctx.module."push-scientific-decimal"([]) == [2.5e-3]
    end

    @tag code: """
         : float-arith-test [
           : add-floats 1.5 2.5 + ;
           : mul-floats 2.0 3.5 * ;
           : div-floats 10.0 4.0 / ;
         ] ; module
         """
    test "arithmetic with floats", ctx do
      assert ctx.module."add-floats"([]) == [4.0]
      assert ctx.module."mul-floats"([]) == [7.0]
      assert ctx.module."div-floats"([]) == [2.5]
    end
  end

  describe "integer underscores" do
    @tag code: """
         : underscore-int-test [
           : push-big 100_000 ;
           : push-million 1_000_000 ;
         ] ; module
         """
    test "integers with underscores", ctx do
      assert ctx.module."push-big"([]) == [100_000]
      assert ctx.module."push-million"([]) == [1_000_000]
    end
  end

  describe "division operator" do
    @tag code: """
         : div-test [
           : divide 10 5 / ;
           : divide-float 10 4 / ;
         ] ; module
         """
    test "division works", ctx do
      assert ctx.module.divide([]) == [2.0]
      assert ctx.module."divide-float"([]) == [2.5]
    end
  end

  describe "recurse" do
    @tag code: """
         : recurse-test [
           : test-recurse-loop
             [
               [
                 : 0 -> ;
                 : _ -> 1 - recurse ;
               ] case
             ] i
             ;
         ] ; module
         """
    test "recurse in quotation via i", ctx do
      # Tests that recurse calls back to the quotation invoked by i
      assert ctx.module."test-recurse-loop"([3]) == [0]
    end
  end
end
