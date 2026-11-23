# Stage 9.13 — Genuine TextEdit RTFD qualification framework

## Scope and limitations

This update extends the source-side **qualification workflow** for the
Priority 2 TextEdit task. No authentic TextEdit-authored package was present
in the source archive and no macOS AppKit/TextEdit runtime is available in the
Debian packaging environment. Accordingly, **genuine TextEdit compatibility
has not been demonstrated** and no source-level fixture is labeled authentic.

The following remain unmodified: the Vala editor, `tools/stickies_rtfd.py`,
existing RTF/RTFD codecs, SQLite schema v7, managed attachment identities,
Majoris-native `majoris.json` payloads, and all existing portable-share
formats. Unsupported RTF/NSFileWrapper constructs are still outside the
supported document subset and should be addressed only after observing a
real TextEdit-generated failure.

## New qualification functionality

`tools/stickies_textedit_qualify.py` now has four explicit commands:

- **`inspect SOURCE.rtfd`** — inspect a bounded directory package and produce
  the existing text/formatting report, now supplemented with per-attachment
  SHA-256, byte sizes, normalized style-run fingerprint and inline-image
  positions. The previous positional `SOURCE.rtfd --expected expected.json`
  syntax continues to work unchanged.
- **`compare SOURCE.rtfd TARGET.rtfd`** — check visible Unicode text,
  canonical spans, attachment bytes (not names) and inline-image bindings.
  Reports a bounded set of lost/added styles and attachment hashes. RTF bytes
  can differ without the document's supported semantics differing.
- **`record SOURCE.rtfd --producer ... --output evidence.json`** — create an
  owner-only, non-overwriting evidence record containing a deterministic
  package fingerprint. A `textedit` producer requires a macOS host and
  `--confirm-textedit-save`; it is an **explicit human attestation**, not
  cryptographic proof that TextEdit produced the document. The record detects
  changed source bytes and mismatched fixture names in later checks.
- **`matrix ORIGINAL.rtfd MAJORIS-EXPORT.rtfd TEXTEDIT-RESAVED.rtfd`** — run
  three independent semantic comparisons and report byte evidence and
  whether records for both TextEdit phases were presented. An equivalent
  result means only that the supported semantic representation matches.
  Actual application operation and visual appearance require separate checks.

All modes are read-only for input packages. The `record` mode writes only
an explicitly named, new evidence file; it refuses overwrites and symlinks.
The implementation reuses the existing bounded RTFD parser and its checks;
attachment hashing uses descriptor-based reads without following a final
symlink. Memory and report sizes remain bounded by the source package limits.

## On a real macOS machine

Use `docs/qualification/textedit-case-matrix.json` to create **actual
TextEdit-authored RTFD documents** (not constructed `TXT.rtf` fixtures). Each
case needs a TextEdit **Save** before being called authentic. The cases cover
custom fonts, point sizes, colors, Unicode, two inline images, indents, tabs,
nested lists, and modifications after a Stickies import. Preserve three
separate directories for a case:

1. `TextEdit-original.rtfd`: created and saved using the TextEdit GUI;
2. `Stickies-export.rtfd`: exported using the running Majoris Stickies GUI;
3. `TextEdit-resaved.rtfd`: opened from the Stickies export, then saved using
   the actual TextEdit GUI under a separate filename.

For a source-level comparison without any claimed provenance:

```sh
python3 tools/stickies_textedit_qualify.py inspect TextEdit-original.rtfd
python3 tools/stickies_textedit_qualify.py compare TextEdit-original.rtfd Stickies-export.rtfd
python3 tools/stickies_textedit_qualify.py matrix TextEdit-original.rtfd Stickies-export.rtfd TextEdit-resaved.rtfd
```

To record user-attested provenance **on macOS only** and produce a triplet
report in a new directory:

```sh
bash tools/macos/qualify_textedit_roundtrip.sh \
  TextEdit-original.rtfd Stickies-export.rtfd TextEdit-resaved.rtfd \
  TextEdit-evidence-case-1
```

This wrapper explicitly asks a human to confirm which application wrote the
packages before recording evidence. It refuses Linux hosts, overwriting
existing records, and nonexistent/non-directory inputs. Avoid running on
private RTFD content you do not intend to inspect. The evidence records
include only package names and checksums, never source text or full paths.

Before approving TextEdit compatibility, also perform the actual **native GUI**
import/export/reimport and review screenshots side by side at 100% and HiDPI
scale, including page layout and image position. Record software versions,
what was visually different, any unsupported constructs, and whether Stickies
retained editable style/attachment semantics. A source-level matrix alone
cannot establish those visual or UI claims.

## Tests and results

New source-side tests exercise same-format comparisons; image filename
regeneration; lost image bytes; changed indentation and image widths;
manifest non-overwrite and stale checks; invalid/absent inline references;
Finder sidecars; legacy CLI compatibility; and platform-gated provenance.
These tests use deliberately **constructed** RTFD packages for regression
and do not count as genuine TextEdit round trips.

```sh
python3 -m unittest discover -s tests/integration -p 'test_stage9_13_textedit_qualification.py' -v
python3 -m unittest discover -s tests/integration -p 'test_*.py' -q
python3 -m unittest discover -s tests/recovery -p 'test_*.py' -q
python3 tools/check_source_docs.py
python3 tools/release_preflight.py
```

**Status:** Qualification harness implemented; real TextEdit fixtures and
macOS GUI/visual comparison **not run** in the source build environment.
Native Vala compilation and Debian binary release qualification remain
separate outstanding gates. The Debian maintainer placeholder must be
replaced by a genuine project contact for a strict release.
