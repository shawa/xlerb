defmodule Xlerb.LexerTest do
  use ExUnit.Case

  describe "string/1" do
    test "lexes numbers" do
      assert :xlerb_lexer.string(~c"1 2 3 4 5 6 7 8 9 0 100 200 4000") ==
               {:ok,
                [
                  {:integer, 1, 1},
                  {:integer, 1, 2},
                  {:integer, 1, 3},
                  {:integer, 1, 4},
                  {:integer, 1, 5},
                  {:integer, 1, 6},
                  {:integer, 1, 7},
                  {:integer, 1, 8},
                  {:integer, 1, 9},
                  {:integer, 1, 0},
                  {:integer, 1, 100},
                  {:integer, 1, 200},
                  {:integer, 1, 4000}
                ], 1}
    end

    test "lexes integers with underscores" do
      assert :xlerb_lexer.string(~c"100_000") == {:ok, [{:integer, 1, 100_000}], 1}
      assert :xlerb_lexer.string(~c"1_000_000") == {:ok, [{:integer, 1, 1_000_000}], 1}
      assert :xlerb_lexer.string(~c"-100_000") == {:ok, [{:integer, 1, -100_000}], 1}
    end

    test "lexes floats" do
      assert :xlerb_lexer.string(~c"3.14") == {:ok, [{:float, 1, 3.14}], 1}
      assert :xlerb_lexer.string(~c"-0.001") == {:ok, [{:float, 1, -0.001}], 1}
      assert :xlerb_lexer.string(~c"1.0") == {:ok, [{:float, 1, 1.0}], 1}
    end

    test "lexes floats with scientific notation" do
      assert :xlerb_lexer.string(~c"1e10") == {:ok, [{:float, 1, 1.0e10}], 1}
      assert :xlerb_lexer.string(~c"1E10") == {:ok, [{:float, 1, 1.0e10}], 1}
      assert :xlerb_lexer.string(~c"2.5e-3") == {:ok, [{:float, 1, 2.5e-3}], 1}
      assert :xlerb_lexer.string(~c"1.5e+10") == {:ok, [{:float, 1, 1.5e10}], 1}
    end

    test "lexes ignore words" do
      assert :xlerb_lexer.string(~c"_") == {:ok, [{:underscore_word, 1, :_}], 1}
      assert :xlerb_lexer.string(~c"_ignored") == {:ok, [{:underscore_word, 1, :_ignored}], 1}
      assert :xlerb_lexer.string(~c"_foo_bar") == {:ok, [{:underscore_word, 1, :_foo_bar}], 1}
    end

    test "lexes basic expressions" do
      assert :xlerb_lexer.string(~c"1 2 + .s") ==
               {:ok, [{:integer, 1, 1}, {:integer, 1, 2}, {:word, 1, :+}, {:word, 1, :".s"}], 1}
    end

    test "lexes definitions" do
      assert :xlerb_lexer.string(~c": square dup * ;") ==
               {:ok,
                [{:":", 1}, {:word, 1, :square}, {:word, 1, :dup}, {:word, 1, :*}, {:";", 1}], 1}
    end

    test "lexes quotations" do
      assert :xlerb_lexer.string(~c"1 2 [dup *] i") ==
               {:ok,
                [
                  {:integer, 1, 1},
                  {:integer, 1, 2},
                  {:"[", 1},
                  {:word, 1, :dup},
                  {:word, 1, :*},
                  {:"]", 1},
                  {:word, 1, :i}
                ], 1}
    end

    test "lexes a full module" do
      assert :xlerb_lexer.string(~c"""
             : Maths [
                : square dup * ;

                : helper foo bar ; private
             ] ; module
             """) ==
               {:ok,
                [
                  {:":", 1},
                  {:word, 1, :Maths},
                  {:"[", 1},
                  {:":", 2},
                  {:word, 2, :square},
                  {:word, 2, :dup},
                  {:word, 2, :*},
                  {:";", 2},
                  {:":", 4},
                  {:word, 4, :helper},
                  {:word, 4, :foo},
                  {:word, 4, :bar},
                  {:";", 4},
                  {:private, 4},
                  {:"]", 5},
                  {:";", 5},
                  {:module, 5}
                ], 6}
    end

    test "lexes atoms" do
      assert :xlerb_lexer.string(~c":foo") == {:ok, [{:atom, 1, :foo}], 1}
      assert :xlerb_lexer.string(~c":bar :baz") == {:ok, [{:atom, 1, :bar}, {:atom, 1, :baz}], 1}
      assert :xlerb_lexer.string(~c":hello_world") == {:ok, [{:atom, 1, :hello_world}], 1}
    end

    test "lexes strings" do
      assert :xlerb_lexer.string(~c"\"hello\"") == {:ok, [{:string, 1, "hello"}], 1}
      assert :xlerb_lexer.string(~c"\"hello world\"") == {:ok, [{:string, 1, "hello world"}], 1}

      assert :xlerb_lexer.string(~c"\"with\\nnewline\"") ==
               {:ok, [{:string, 1, "with\nnewline"}], 1}

      assert :xlerb_lexer.string(~c"\"escaped\\\"quote\"") ==
               {:ok, [{:string, 1, "escaped\"quote"}], 1}
    end

    test "lexes capture syntax tokens" do
      assert :xlerb_lexer.string(~c"&") == {:ok, [{:&, 1}], 1}
      assert :xlerb_lexer.string(~c"&1") == {:ok, [{:capture_var, 1, 1}], 1}

      assert :xlerb_lexer.string(~c"&2 &3") ==
               {:ok, [{:capture_var, 1, 2}, {:capture_var, 1, 3}], 1}
    end

    test "lexes map-related tokens" do
      assert :xlerb_lexer.string(~c"%") == {:ok, [{:%, 1}], 1}
      assert :xlerb_lexer.string(~c"=>") == {:ok, [{:"=>", 1}], 1}
      assert :xlerb_lexer.string(~c"{ }") == {:ok, [{:"{", 1}, {:"}", 1}], 1}
    end

    test "lexes atom keys" do
      assert :xlerb_lexer.string(~c"foo:") == {:ok, [{:atom_key, 1, :foo}], 1}

      assert :xlerb_lexer.string(~c"bar: baz:") ==
               {:ok, [{:atom_key, 1, :bar}, {:atom_key, 1, :baz}], 1}
    end

    test "lexes list patterns tokens" do
      assert :xlerb_lexer.string(~c"|") == {:ok, [{:|, 1}], 1}
      assert :xlerb_lexer.string(~c",") == {:ok, [{:",", 1}], 1}
    end

    test "lexes complex capture expression tokens" do
      assert :xlerb_lexer.string(~c"&%{&1 => &2}") ==
               {:ok,
                [
                  {:&, 1},
                  {:%, 1},
                  {:"{", 1},
                  {:capture_var, 1, 1},
                  {:"=>", 1},
                  {:capture_var, 1, 2},
                  {:"}", 1}
                ], 1}
    end

    test "lexes capture expression with atom keys" do
      assert :xlerb_lexer.string(~c"&%{foo: &1, bar: &2}") ==
               {:ok,
                [
                  {:&, 1},
                  {:%, 1},
                  {:"{", 1},
                  {:atom_key, 1, :foo},
                  {:capture_var, 1, 1},
                  {:",", 1},
                  {:atom_key, 1, :bar},
                  {:capture_var, 1, 2},
                  {:"}", 1}
                ], 1}
    end

    test "lexes capture expression with list" do
      assert :xlerb_lexer.string(~c"&[&1 | &2]") ==
               {:ok,
                [
                  {:&, 1},
                  {:"[", 1},
                  {:capture_var, 1, 1},
                  {:|, 1},
                  {:capture_var, 1, 2},
                  {:"]", 1}
                ], 1}
    end

    test "lexes capture expression with tuple" do
      assert :xlerb_lexer.string(~c"&{&1, &2, &3}") ==
               {:ok,
                [
                  {:&, 1},
                  {:"{", 1},
                  {:capture_var, 1, 1},
                  {:",", 1},
                  {:capture_var, 1, 2},
                  {:",", 1},
                  {:capture_var, 1, 3},
                  {:"}", 1}
                ], 1}
    end
  end
end
