defmodule Xlerb.PackUnpackTest do
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

  describe "pack with maps" do
    @tag code: """
         : pack-test [
           : test-map-pack 300 400 &%{&1 => &2} pack ;
         ] ; module
         """
    test "packs two values into map with => syntax", ctx do
      assert ctx.module."test-map-pack"([]) == [%{400 => 300}]
    end

    @tag code: """
         : pack-test [
           : test-map-atom-keys 100 200 &%{foo: &1, bar: &2} pack ;
         ] ; module
         """
    test "packs values into map with atom keys", ctx do
      assert ctx.module."test-map-atom-keys"([]) == [%{foo: 200, bar: 100}]
    end

    @tag code: """
         : pack-test [
           : test-nested-map 1 2 3 &%{outer: &1, inner: %{a: &2, b: &3}} pack ;
         ] ; module
         """
    test "packs values into nested map", ctx do
      assert ctx.module."test-nested-map"([]) == [%{outer: 3, inner: %{a: 2, b: 1}}]
    end
  end

  describe "pack with tuples" do
    @tag code: """
         : pack-test [
           : test-tuple-pack 1 2 3 &{&1, &2, &3} pack ;
         ] ; module
         """
    test "packs three values into tuple", ctx do
      assert ctx.module."test-tuple-pack"([]) == [{3, 2, 1}]
    end

    @tag code: """
         : pack-test [
           : test-two-tuple 10 20 &{&1, &2} pack ;
         ] ; module
         """
    test "packs two values into tuple", ctx do
      assert ctx.module."test-two-tuple"([]) == [{20, 10}]
    end
  end

  describe "pack with lists" do
    @tag code: """
         : pack-test [
           : test-list-pack 1 2 3 &[&1, &2, &3] pack ;
         ] ; module
         """
    test "packs three values into list", ctx do
      assert ctx.module."test-list-pack"([]) == [[3, 2, 1]]
    end

    @tag code: """
         : pack-test [
           : test-list-cons 10 &[&1 | &2] pack ;
         ] ; module
         """
    test "packs values into list with cons", ctx do
      result = ctx.module."test-list-cons"([[20, 30]])
      assert result == [[10, 20, 30]]
    end
  end

  describe "unpack with maps" do
    @tag code: """
         : pack-test [
           : test-map-unpack &%{400 => &1} unpack ;
         ] ; module
         """
    test "unpacks map value", ctx do
      assert ctx.module."test-map-unpack"([%{400 => 300}]) == [300]
    end

    @tag code: """
         : pack-test [
           : test-map-atom-keys-unpack &%{foo: &1, bar: &2} unpack ;
         ] ; module
         """
    test "unpacks map with atom keys", ctx do
      assert ctx.module."test-map-atom-keys-unpack"([%{foo: 100, bar: 200}]) == [100, 200]
    end

    @tag code: """
         : pack-test [
           : test-map-unpack-error &%{missing: &1} unpack ;
         ] ; module
         """
    test "raises MatchError on failed map unpack", ctx do
      assert_raise MatchError, fn ->
        ctx.module."test-map-unpack-error"([%{foo: 100}])
      end
    end
  end

  describe "unpack with tuples" do
    @tag code: """
         : pack-test [
           : test-tuple-unpack &{&1, &2, &3} unpack ;
         ] ; module
         """
    test "unpacks tuple into three values", ctx do
      assert ctx.module."test-tuple-unpack"([{1, 2, 3}]) == [1, 2, 3]
    end

    @tag code: """
         : pack-test [
           : test-tuple-unpack-error &{&1, &2, &3} unpack ;
         ] ; module
         """
    test "raises MatchError on tuple size mismatch", ctx do
      assert_raise MatchError, fn ->
        ctx.module."test-tuple-unpack-error"([{1, 2}])
      end
    end
  end

  describe "unpack with lists" do
    @tag code: """
         : pack-test [
           : test-list-unpack &[&1, &2, &3] unpack ;
         ] ; module
         """
    test "unpacks list into values", ctx do
      assert ctx.module."test-list-unpack"([[1, 2, 3]]) == [1, 2, 3]
    end

    @tag code: """
         : pack-test [
           : test-list-cons-unpack &[&1 | &2] unpack ;
         ] ; module
         """
    test "unpacks list with cons pattern", ctx do
      assert ctx.module."test-list-cons-unpack"([[1, 2, 3]]) == [1, [2, 3]]
    end
  end

  describe "round-trip pack and unpack" do
    @tag code: """
         : pack-test [
           : test-roundtrip 100 200 &%{a: &1, b: &2} pack &%{a: &1, b: &2} unpack ;
         ] ; module
         """
    test "pack then unpack returns original values", ctx do
      assert ctx.module."test-roundtrip"([]) == [200, 100]
    end

    @tag code: """
         : pack-test [
           : test-tuple-roundtrip 1 2 3 &{&1, &2, &3} pack &{&1, &2, &3} unpack ;
         ] ; module
         """
    test "tuple pack and unpack roundtrip", ctx do
      assert ctx.module."test-tuple-roundtrip"([]) == [3, 2, 1]
    end
  end

  describe "complex nested structures" do
    @tag code: """
         : pack-test [
           : test-complex :status 42 "message" &%{status: &1, code: &2, msg: &3} pack ;
         ] ; module
         """
    test "packs mixed types into map", ctx do
      assert ctx.module."test-complex"([]) == [%{status: "message", code: 42, msg: :status}]
    end

    @tag code: """
         : pack-test [
           : test-nested-unpack &%{data: %{x: &1, y: &2}} unpack ;
         ] ; module
         """
    test "unpacks from nested map structure", ctx do
      assert ctx.module."test-nested-unpack"([%{data: %{x: 10, y: 20}}]) == [10, 20]
    end

    @tag code: """
         : pack-test [
           : test-list-of-tuples 1 2 3 4 &[{&1, &2}, {&3, &4}] pack ;
         ] ; module
         """
    test "packs into list of tuples", ctx do
      assert ctx.module."test-list-of-tuples"([]) == [[{4, 3}, {2, 1}]]
    end
  end

  describe "stack behavior" do
    @tag code: """
         : pack-test [
           : test-stack-preservation 999 100 200 &{&1, &2} pack ;
         ] ; module
         """
    test "preserves remaining stack after pack", ctx do
      assert ctx.module."test-stack-preservation"([]) == [{200, 100}, 999]
    end

    @tag code: """
         : pack-test [
           : test-unpack-stack-preservation &{&1, &2} unpack ;
         ] ; module
         """
    test "preserves remaining stack after unpack", ctx do
      assert ctx.module."test-unpack-stack-preservation"([{10, 20}, 999]) == [10, 20, 999]
    end
  end
end
