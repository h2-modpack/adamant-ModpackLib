# Hash String Compression

Future direction. Canonical hashes should stay semantic and additive:

```text
_v=2|ModuleId=1|ModuleId.alias=value
```

If share strings become too long, first benchmark compressing the final
canonical string as a transport/display layer. Reintroduce semantic packing
only if real module hashes prove generic compression is not enough.

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

## Root Layout Manifest

A narrower future option is an author-owned root ordering manifest, not a
bit-packing schema:

```lua
hash = {
    packLayout = {
        "Enabled",
        "PriorityBiome1",
        "PriorityBiome2",
        "SomePackedFlags",
    },
}
```

This would mean: process these fixed-width storage roots in this order for
compact hash encoding. Lib would still own all mechanics:

- whether a root can participate;
- bool, bounded-int, and packed-int width math;
- crossing 32-bit or transport-token boundaries;
- encoding and decoding;
- missing trailing values falling back to defaults.

Authors would not count bits or define buckets. They would only pin ABI order so
future fields can be appended instead of inserted into the middle of a compact
stream.

This should stay narrow:

- only fixed-width roots participate: `bool`, `packedInt`, and bounded `int`;
- strings and unbounded integers remain in the semantic key/value section;
- table schemas and control templates own their own local ordering;
- root layout does not reach into table cells or generated control aliases.

Reordering or inserting in the middle of a layout is a compatibility event.
Appending at the end can be additive if the decoder treats missing trailing
values as defaults.

## Preferred Direction

Keep the canonical hash as a stable key/value map, then benchmark an optional
transport layer:

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

Whole-string compression has the better engineering profile:

- no second author-facing schema;
- no layout maintenance;
- works across strings, unbounded ints, tables, controls, aliases, delimiters,
  and repeated module ids;
- can be changed behind `HASH_VERSION`;
- avoids author mistakes that reorder compact streams.

Semantic packing can compress dense bool/int configurations better because it
uses prepared width metadata. The question is whether the extra API surface is
worth it on real hashes. Measure GodPool, BiomeControl, BoonBans, and any other
large profile-heavy modules before adding `packLayout`.

## Useful Groundwork That Remains

Storage preparation still stamps honest hash metadata for scalar types:

- `bool` has `_packWidth = 1`;
- bounded integer `int` may declare `width`;
- `packedInt` requires explicit root `width`;
- packed child ranges/defaults are validated against declared bit widths.

That metadata is useful for validation and possible local codecs. It should not
automatically become an author-facing root hash layout. If root layout returns,
it should be opt-in and should only order roots; Lib should still own packing.

## Tables And Controls

Do not flatten live table/control storage just to shorten hashes. If table or
control hashes need specialized codecs later, keep them local to that composite
boundary and version them deliberately.

The default path should remain semantic storage roots plus optional whole-string
compression.
