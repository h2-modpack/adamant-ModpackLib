# Hash String Compression

Future direction. Canonical hashes should stay semantic and additive:

```text
_v=2|ModuleId=1|ModuleId.alias=value
```

If share strings become too long, compress the final canonical string as a
transport/display layer instead of reintroducing schema-level bit grouping.

## Why Not Hash Groups

Manual hash groups were removed because they made module authors maintain a
bit-level ABI. They compressed flat scalar roots well, but the maintenance cost
was high:

- authors had to count bits and preserve manual layouts;
- tables and controls did not fit the flat alias model cleanly;
- generated private control aliases would have leaked into public hash policy;
- changing a packed layout could make old hashes unrecoverable without keeping
  historical layouts around.

Automatic greedy packing has the opposite tradeoff: it removes author burden,
but adding a storage field can shift positional bits and invalidate old profile
data. A layout fingerprint can prevent silent corruption, but it cannot recover
old values.

## Preferred Direction

Keep the canonical hash as a stable key/value map, then optionally add:

```text
canonical semantic hash -> compressed share string
compressed share string -> canonical semantic hash -> apply
```

Candidate techniques:

- LZW-style string compression;
- base-N encodings tuned for the game/input surface;
- dictionary compression over repeated module ids, aliases, delimiters, and
  common values.

This keeps ordinary schema additions additive: missing new keys still fall back
to defaults, and old keys keep their meaning.

## Useful Groundwork That Remains

Storage preparation still stamps honest hash metadata for scalar types:

- `bool` has `_packWidth = 1`;
- bounded integer `int` may declare `width`;
- `packedInt` requires explicit root `width`;
- packed child ranges/defaults are validated against declared bit widths.

That metadata is useful for validation and possible local codecs, but it should
not become an author-facing root hash layout.

## Tables And Controls

Do not flatten live table/control storage just to shorten hashes. If table or
control hashes need specialized codecs later, keep them local to that composite
boundary and version them deliberately.

The default path should remain semantic storage roots plus optional whole-string
compression.
