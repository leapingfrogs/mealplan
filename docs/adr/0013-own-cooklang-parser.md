# 13. Write our own Cooklang parser

- Status: accepted
- Date: 2026-10-20

## Context

Recipes are stored as Cooklang text (iteration 1 design). The app parses that
text to show steps and a live preview, store ingredients as rows, and scale and
merge them for shopping. Parsing runs on every keystroke in the editor and on
every save. The input is user-supplied text, so the parser must never crash or
hang.

Before writing one we checked for an existing Elixir parser (October 2026):

- **Hex:** `cooklang_ex` (0.0.1-alpha3, last release December 2025, about 180
  downloads) is the only package. It wraps the Rust `cooklang-rs` parser as a
  Rustler NIF and compiles it from source, so it needs a Rust toolchain. That
  means Rust in devenv, CI and the Docker build, and a tree of Cargo crates to
  vet and pin.
- **GitHub:** `jtormey/cooklang-elixir` is also a Rust NIF, has seven commits
  and no licence.
- **Cooklang's list of implementations** (cooklang.org, For Developers) has
  parsers in 15 languages but none in Elixir or Erlang.

## Decision

Write `Mealplan.Cooklang` ourselves, in plain Elixir (binary matching and
Unicode-aware regular expressions), with no runtime dependency.

- Target the base Cooklang specification (version 8). It must pass the spec's
  canonical tests, which are vendored unchanged in
  `test/support/fixtures/cooklang/` and pinned to a spec commit. They are read
  with `yaml_elixir`, which is already locked through `mix_audit`; we add it as
  a test-only dependency, with `stream_data` for the property tests.
- `cooklang-rs`'s extensions (references to other recipes, ranges, unit
  conversion syntax and so on) are out of scope.
- For front-matter metadata we accept the flat `key: value` subset that the
  spec tests use. Anything else becomes a warning rather than an error. We
  don't parse full YAML from user input at runtime.
- The parser is a pure function from text to a result with warnings. It never
  raises on any input; property tests check this.
- Normalising ingredients for storage (key, canonical unit and dimension,
  whether it scales) is our own code on top of the parse result.

## Consequences

- No native code, Rust toolchain or extra runtime dependency; the parser builds
  with the rest of the app and is covered by our quality gates.
- We own the parser's bugs and its upkeep as the spec evolves. The vendored
  tests make spec changes an explicit update.
- We give up `cooklang-rs`'s extensions and its unit conversion and scaling.
  Iteration 1 needs only grams to kilograms and millilitres to litres, which
  the design already covers in our own code.
- If a maintained, pure-Elixir parser appears, this decision should be
  revisited.

## Amendment (2026-10-20, while implementing)

This record first chose [NimbleParsec](https://hex.pm/packages/nimble_parsec).
While writing the parser, a hand-written one proved simpler. Cooklang is
line-based: paragraphs, comments, front matter, sections and notes are
handled line by line. Within a line, the spec tests end a one-word name at
any Unicode whitespace or punctuation (for example U+2009 and `⸫`).
NimbleParsec matches character ranges, not Unicode categories, so it would
have needed workarounds that rewrite its input. The other decisions are
unchanged.
