defmodule Xlerb.ParserTest.Helpers do
  def lex!(str) do
    {:ok, tokens, _} =
      str
      |> String.to_charlist()
      |> :xlerb_lexer.string()

    tokens
  end

  def sigil_x(str, _) do
    lex!(str)
  end
end

defmodule Xlerb.ParserTest do
  import Xlerb.ParserTest.Helpers, only: [sigil_x: 2]
  import :xlerb_parser, only: [parse: 1]
  use ExUnit.Case

  describe "parse/1" do
    test "parses a bare number" do
      assert parse(~x"1") ==
               {:ok, {:program, [integer: 1]}}
    end

    test "parses a basic expression" do
      assert parse(~x"1 2 +") ==
               {:ok, {:program, [integer: 1, integer: 2, word: :+]}}
    end

    test "parses a multiline expression" do
      assert parse(~x"""
             1 2 +
             2 *
             .s
             """) ==
               {:ok,
                {:program, [integer: 1, integer: 2, word: :+, integer: 2, word: :*, word: :".s"]}}
    end

    test "parses a word definition" do
      assert parse(~x": a-word body ;") ==
               {:ok, {:program, [{:def, :"a-word", [], [word: :body]}]}}
    end

    test "parses a private word definition" do
      assert parse(~x": a-word body ; private") ==
               {:ok, {:program, [{:defp, :"a-word", [], [word: :body]}]}}
    end

    test "parses a module definition" do
      assert parse(~x": my-module [
        : public 1 2 ;
        : priv some other ; private
      ] ; module") ==
               {:ok,
                {:program,
                 [
                   {:defmodule, :"my-module", [],
                    [
                      quotation: [
                        {:def, :public, [], [integer: 1, integer: 2]},
                        {:defp, :priv, [], [word: :some, word: :other]}
                      ]
                    ]}
                 ]}}
    end

    test "parses a case statement" do
      assert parse(~x"[ : 0 -> 0 ; ] case") ==
               {:ok,
                {:program,
                 [
                   {:case, [{:def, :->, [0], [integer: 0]}]}
                 ]}}
    end

    test "parses a case statement with multiple arms" do
      assert parse(~x"[ : 0 -> 0 ; : 10 -> 100 ; : _ -> 50 ; ] case") ==
               {:ok,
                {:program,
                 [
                   {:case,
                    [
                      {:def, :->, [0], [integer: 0]},
                      {:def, :->, [10], [integer: 100]},
                      {:def, :->, [:_], [integer: 50]}
                    ]}
                 ]}}
    end

    test "parses a case statement with expressions in arms" do
      assert parse(~x"[ : 10 -> drop 100 ; ] case") ==
               {:ok,
                {:program,
                 [
                   {:case, [{:def, :->, [10], [word: :drop, integer: 100]}]}
                 ]}}
    end

    test "parses capture with tuple" do
      assert parse(~x"&{&1, &2}") ==
               {:ok,
                {:program,
                 [
                   {:capture,
                    [
                      {:"{", 1},
                      {:capture_var, 1, 1},
                      {:",", 1},
                      {:capture_var, 1, 2},
                      {:"}", 1}
                    ]}
                 ]}}
    end

    test "parses capture with map" do
      assert parse(~x"&%{&1 => &2}") ==
               {:ok,
                {:program,
                 [
                   {:capture,
                    [
                      {:%, 1},
                      {:"{", 1},
                      {:capture_var, 1, 1},
                      {:"=>", 1},
                      {:capture_var, 1, 2},
                      {:"}", 1}
                    ]}
                 ]}}
    end

    test "parses capture with map and atom keys" do
      assert parse(~x"&%{foo: &1}") ==
               {:ok,
                {:program,
                 [
                   {:capture,
                    [
                      {:%, 1},
                      {:"{", 1},
                      {:atom_key, 1, :foo},
                      {:capture_var, 1, 1},
                      {:"}", 1}
                    ]}
                 ]}}
    end

    test "parses capture with list" do
      assert parse(~x"&[&1 | &2]") ==
               {:ok,
                {:program,
                 [
                   {:capture,
                    [
                      {:"[", 1},
                      {:capture_var, 1, 1},
                      {:|, 1},
                      {:capture_var, 1, 2},
                      {:"]", 1}
                    ]}
                 ]}}
    end
  end
end
