Definitions.

UNDERSCORE_WORD_WITH_COLONS = _[_0-9a-zA-Z~`!@#$*+\\=/.-]*:[_0-9a-zA-Z~`!@#$*+\\=/.:-]+
UNDERSCORE_WORD             = _[_0-9a-zA-Z~`!@#$*+\\=/.-]*
WORD_WITH_COLONS            = [0-9a-zA-Z~`!@#$*+\\=/.-][_0-9a-zA-Z~`!@#$*+\\=/.-]*:[_0-9a-zA-Z~`!@#$*+\\=/.:-]+
WORD                        = [0-9a-zA-Z~`!@#$*+\\=/.-][_0-9a-zA-Z~`!@#$*+\\=/.-]*
FLOAT                       = -?[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?
FLOAT_EXP                   = -?[0-9]+[eE][+-]?[0-9]+
INT                         = -?[0-9][0-9_]*
ATOM                        = :[a-zA-Z_][a-zA-Z0-9_]*
ATOM_KEY                    = [a-zA-Z_][a-zA-Z0-9_]*:
CAPTURE_VAR                 = &[0-9]+
STRING                      = "([^"\\]|\\.)*"
WHITESPACE                  = [\s\t\n\r]+

Rules.

{WHITESPACE}   : skip_token.

\[             : {token, {'[', TokenLine}}.
\]             : {token, {']', TokenLine}}.
\{             : {token, {'{', TokenLine}}.
\}             : {token, {'}', TokenLine}}.
;              : {token, {';', TokenLine}}.
->             : {token, {'->', TokenLine}}.
=>             : {token, {'=>', TokenLine}}.
,              : {token, {',', TokenLine}}.
\|             : {token, {'|', TokenLine}}.
\%             : {token, {'%', TokenLine}}.

private        : {token, {private, TokenLine}}.
module         : {token, {module, TokenLine}}.
case           : {token, {'case', TokenLine}}.
receive        : {token, {'receive', TokenLine}}.

{FLOAT}                         : {token, {float, TokenLine, parse_float(TokenChars)}}.
{FLOAT_EXP}                     : {token, {float, TokenLine, parse_float(TokenChars)}}.
{INT}                           : {token, {integer, TokenLine, parse_integer(TokenChars)}}.
{CAPTURE_VAR}                   : {token, {capture_var, TokenLine, list_to_integer(tl(TokenChars))}}.
{ATOM}                          : {token, {atom, TokenLine, list_to_atom(tl(TokenChars))}}.
{ATOM_KEY}                      : {token, {atom_key, TokenLine, list_to_atom(lists:droplast(TokenChars))}}.
{STRING}                        : {token, {string, TokenLine, unescape_string(TokenChars)}}.
{UNDERSCORE_WORD_WITH_COLONS}   : {token, {underscore_word, TokenLine, list_to_atom(TokenChars)}}.
{UNDERSCORE_WORD}               : {token, {underscore_word, TokenLine, list_to_atom(TokenChars)}}.
{WORD_WITH_COLONS}              : {token, {word, TokenLine, list_to_atom(TokenChars)}}.
{WORD}                          : {token, {word, TokenLine, list_to_atom(TokenChars)}}.
&              : {token, {'&', TokenLine}}.
:                               : {token, {':', TokenLine}}.

Erlang code.

unescape_string(TokenChars) ->
    String = lists:sublist(TokenChars, 2, length(TokenChars) - 2),
    list_to_binary(unescape_chars(String)).

unescape_chars([]) -> [];
unescape_chars([$\\, $n | Rest]) -> [$\n | unescape_chars(Rest)];
unescape_chars([$\\, $t | Rest]) -> [$\t | unescape_chars(Rest)];
unescape_chars([$\\, $r | Rest]) -> [$\r | unescape_chars(Rest)];
unescape_chars([$\\, $" | Rest]) -> [$" | unescape_chars(Rest)];
unescape_chars([$\\, $\\ | Rest]) -> [$\\ | unescape_chars(Rest)];
unescape_chars([C | Rest]) -> [C | unescape_chars(Rest)].

% Parse integer, stripping underscores for readability
parse_integer(TokenChars) ->
    Stripped = lists:filter(fun(C) -> C =/= $_ end, TokenChars),
    list_to_integer(Stripped).

% Parse float (handles scientific notation too)
parse_float(TokenChars) ->
    list_to_float(normalize_float(TokenChars)).

% Normalize float string to ensure it has decimal point for list_to_float
normalize_float(TokenChars) ->
    case lists:member($., TokenChars) of
        true -> TokenChars;
        false ->
            % Scientific notation without decimal point, e.g. "1e10" -> "1.0e10"
            case string:chr(TokenChars, $e) of
                0 ->
                    case string:chr(TokenChars, $E) of
                        0 -> TokenChars ++ ".0";
                        EPos -> insert_decimal_before(TokenChars, EPos)
                    end;
                EPos -> insert_decimal_before(TokenChars, EPos)
            end
    end.

insert_decimal_before(Chars, Pos) ->
    {Before, After} = lists:split(Pos - 1, Chars),
    Before ++ ".0" ++ After.
