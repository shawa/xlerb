Nonterminals 
    expression 
    expression_list 
    quotation 
    word_definition
    module_definition
    case_expression
    receive_expression
    pattern_literal
    pattern_literals
    capture_expression
    capture_structure
    capture_map
    capture_tuple
    capture_list
    capture_map_pairs
    capture_map_pair
    capture_list_items
    capture_elements
    capture_term
    program.

Terminals
    '['
    ']'
    '{'
    '}'
    ':'
    ';'
    '->'
    '=>'
    ','
    '|'
    '%'
    '&'
    integer
    float
    atom
    atom_key
    string
    capture_var
    special_form
    word
    underscore_word
    private
    module
    'case'
    'receive'.
  
Rootsymbol program.


expression -> word_definition : '$1'.
expression -> module_definition : '$1'.
expression -> case_expression : '$1'.
expression -> receive_expression : '$1'.
expression -> quotation : '$1'.
expression -> capture_expression : '$1'.
expression -> integer : {integer, element(3, '$1')}.
expression -> float : {float, element(3, '$1')}.
expression -> atom : {atom, element(3, '$1')}.
expression -> string : {string, element(3, '$1')}.
expression -> word : {word, element(3, '$1')}.
expression -> underscore_word : {word, element(3, '$1')}.
expression -> special_form : {special_form, element(3, '$1')}.

expression_list -> expression expression_list : ['$1' | '$2'].
expression_list -> '$empty' : [].

quotation -> '[' expression_list ']' : {quotation, '$2'}.

pattern_literal -> integer : element(3, '$1').
pattern_literal -> underscore_word : '_'.
pattern_literals -> pattern_literal pattern_literals : ['$1' | '$2'].
pattern_literals -> '$empty' : [].

word_definition -> ':' pattern_literals word expression_list ';' private : {defp, element(3, '$3'), '$2', '$4'}.
word_definition -> ':' pattern_literals word expression_list ';' : {def, element(3, '$3'), '$2', '$4'}.
word_definition -> ':' pattern_literals underscore_word expression_list ';' private : {defp, element(3, '$3'), '$2', '$4'}.
word_definition -> ':' pattern_literals underscore_word expression_list ';' : {def, element(3, '$3'), '$2', '$4'}.
word_definition -> ':' pattern_literals '->' expression_list ';' private : {defp, '->', '$2', '$4'}.
word_definition -> ':' pattern_literals '->' expression_list ';' : {def, '->', '$2', '$4'}.

case_expression -> quotation 'case' : {'case', element(2, '$1')}.
receive_expression -> quotation 'receive' : {'receive', element(2, '$1')}.

module_definition -> ':' pattern_literals word expression_list ';' module : {defmodule, element(3, '$3'), '$2', '$4'}.
module_definition -> ':' pattern_literals underscore_word expression_list ';' module : {defmodule, element(3, '$3'), '$2', '$4'}.

capture_structure -> capture_map : '$1'.
capture_structure -> capture_tuple : '$1'.
capture_structure -> capture_list : '$1'.

capture_map -> '%' '{' '}' : [{'%', 1}, {'{', 1}, {'}', 1}].
capture_map -> '%' '{' capture_map_pairs '}' : [{'%', 1}, {'{', 1} | '$3'] ++ [{'}', 1}].

capture_tuple -> '{' '}' : [{'{', 1}, {'}', 1}].
capture_tuple -> '{' capture_elements '}' : [{'{', 1} | '$2'] ++ [{'}', 1}].

capture_list -> '[' ']' : [{'[', 1}, {']', 1}].
capture_list -> '[' capture_list_items ']' : [{'[', 1} | '$2'] ++ [{']', 1}].

capture_map_pairs -> capture_map_pair : '$1'.
capture_map_pairs -> capture_map_pair ',' capture_map_pairs : '$1' ++ [{',', 1} | '$3'].

capture_map_pair -> capture_term '=>' capture_term : flatten_list('$1') ++ [{'=>', 1} | flatten_list('$3')].
capture_map_pair -> atom_key capture_term : ['$1' | flatten_list('$2')].

capture_list_items -> capture_term : flatten_list('$1').
capture_list_items -> capture_term '|' capture_term : flatten_list('$1') ++ [{'|', 1} | flatten_list('$3')].
capture_list_items -> capture_term ',' capture_list_items : flatten_list('$1') ++ [{',', 1} | '$3'].

capture_elements -> capture_term : flatten_list('$1').
capture_elements -> capture_term ',' capture_elements : flatten_list('$1') ++ [{',', 1} | '$3'].

capture_term -> capture_var : '$1'.
capture_term -> integer : '$1'.
capture_term -> float : '$1'.
capture_term -> atom : '$1'.
capture_term -> string : '$1'.
capture_term -> capture_structure : '$1'.

capture_expression -> '&' capture_structure : {capture, '$2'}.

program -> expression_list : {program, '$1'}.


Erlang code.

flatten_list(X) when is_list(X) -> X;
flatten_list(X) -> [X].
