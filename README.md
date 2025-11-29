# Xlerb

**A stack-oriented language for the BEAM**

[![v0.0.1](https://img.shields.io/badge/version-0.0.1-blue.svg)](https://github.com/shawa/xlerb/releases/tag/v0.0.1)

Xlerb is a concatenative, stack-based language targeting the Erlang Runtime System. It combines the point-free elegance of Forth and Joy with the rock-solid concurrency of the BEAM.

```xlerb
: ping-server
  [
    : _from :ping -> drop ! :pong send ;
    : _from     _ -> drop drop ;
  ] receive
  ping-server ;

[ping-server] spawn
```

📖 **[Full documentation at xlerb.wtf](https://xlerb.wtf)**

---

## Quick Start

```sh
# Build the compiler
mix escript.build

# Start the REPL
./xlerb repl
```

```
xlerb[0]> 1 2 3
xlerb[3]> + .
5
xlerb[1]> dup * .
1
xlerb[0]>
```

## Features

### Stack Operations

```xlerb
1 2 3           \ Push values onto the stack
dup             \ Duplicate top: a -- a a  
drop            \ Discard top: a --
swap            \ Swap top two: a b -- b a
rot             \ Rotate three: a b c -- c a b
.               \ Print and pop top
.s              \ Print entire stack
```

### Arithmetic

```xlerb
10 3 + .        \ => 13
10 3 - .        \ => 7  
10 3 * .        \ => 30
10 4 / .        \ => 2.5
```

### Word Definitions

```xlerb
: square dup * ;

5 square .      \ => 25
```

### Pattern Matching

Match on the stack to create multi-clause words:

```xlerb
: 0 factorial drop 1 ;
: _ factorial dup 1 - factorial * ;

5 factorial .   \ => 120
```

### Quotations

Code as data, invoked with `i`:

```xlerb
200 [dup *] i . \ => 40000

[1 +] 5 swap i .  \ => 6
```

### Case Expressions

```xlerb
[
  : 0 -> "zero" ;
  : 1 -> "one" ;
  : _ -> "other" ;
] case
```

### Modules

```xlerb
: math [
  : square dup * ;
  : cube dup dup * * ;
  : helper internal-stuff ; private
] ; module

5 math:square . \ => 25
```

### Processes & Messages

```xlerb
self                    \ Push current PID
[quotation] spawn       \ Spawn process, push PID

pid ! :hello 42 send    \ Send message to pid

[
  : _from :ping -> ! :pong send ;
] receive               \ Pattern match on messages
```

### Elixir/Erlang FFI

```xlerb
"hello" "world" [String concat 2] elixir .
\ => "helloworld"
```

### Pack & Unpack

Work with composite data structures:

```xlerb
1 2 3 &{&1, &2, &3} pack .
\ => {3, 2, 1}

%{name: "alice"} &%{name: &1} unpack .
\ => "alice"
```

## CLI Commands

```sh
./xlerb repl              # Interactive REPL with history
./xlerb run '<code>'      # Execute xlerb code
./xlerb compile           # Compile .xlb files from lib/
```

## Data Types

| Type | Examples |
|------|----------|
| Integers | `42`, `-17`, `100_000` |
| Floats | `3.14`, `-0.001`, `1e10`, `2.5e-3` |
| Atoms | `:ok`, `:error`, `:my_atom` |
| Strings | `"hello"`, `"line\nbreak"` |
| Booleans | `true`, `false` |

## Requirements

- Elixir 1.18+
- Erlang/OTP 28+

I'd just use [asdf](https://asdf-vm.com/) for version management: The repo includes a `.tool-versions` file.

```sh
git clone https://github.com/shawa/xlerb
cd xlerb
asdf install
```

## Building

```sh
mix escript.build
```

## Running Tests

```sh
mix test
```

## Learn More

- 📖 [Language Specification](https://xlerb.wtf/spec/)
- 🎓 [Learning Guide](https://xlerb.wtf/learn/)
- ❓ [WTF is Xlerb?](https://xlerb.wtf/wtf/)
- 📦 [Releases](https://xlerb.wtf/releases/)

## License

MIT License - See [LICENSE](LICENSE) for details.

---

*The 'Xlerb?' name and butler character is from [Starting Forth](https://www.forth.com/starting-forth/) by Leo Brodie.*
