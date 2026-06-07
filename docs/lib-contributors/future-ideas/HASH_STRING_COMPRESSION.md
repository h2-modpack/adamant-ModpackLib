# Hash String Compression

Future direction. Canonical hashes should stay semantic and additive:

```text
_v=2|ModuleId=1|ModuleId.alias=value
```

If share strings become too long, benchmark compressing the final canonical
string as a transport/display layer:

```text
canonical semantic hash -> compressed share string
compressed share string -> canonical semantic hash -> apply
```

## Why Not Semantic Packing

Manual hash groups were removed because they made module authors maintain a
bit-level ABI. They compressed flat scalar roots well, but the maintenance cost
was high:

- authors had to count bits and preserve manual layouts;
- tables and controls did not fit the flat alias model cleanly;
- generated private control aliases would have leaked into public hash policy;
- changing a packed layout could make existing hashes unrecoverable without keeping
  historical layouts around.

Automatic greedy packing has the opposite tradeoff: it removes author burden,
but adding a storage field can shift positional bits and invalidate existing
profile data. A layout fingerprint can prevent silent corruption, but it cannot
recover existing values.

For now, keep packing only where it is explicit storage behavior:
`packedInt` roots and their declared bit children.

## Preferred Direction

Keep the canonical hash as a stable key/value map, then benchmark an optional
transport layer.

Candidate techniques:

- LZW-style string compression;
- base-N encodings tuned for the game/input surface;
- dictionary compression over repeated module ids, aliases, delimiters, and
  common values.

This keeps ordinary schema additions additive: missing new keys still fall back
to defaults, and existing keys keep their meaning.

Whole-string compression has the better engineering profile:

- no second author-facing schema;
- no layout maintenance;
- works across strings, unbounded ints, tables, controls, aliases, delimiters,
  and repeated module ids;
- can be changed behind `HASH_VERSION`;
- avoids author mistakes that reorder compact streams.

Measure GodPool, BiomeControl, BoonBans, and any other large profile-heavy
modules before adding compression.

## Tables And Controls

Do not flatten live table/control storage just to shorten hashes. Table storage
should stay operationally table-shaped at runtime; hashing can serialize a
deterministic snapshot when needed.

The default path should remain semantic storage roots plus optional whole-string
compression.
