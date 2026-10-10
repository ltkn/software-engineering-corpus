# Attribution — vendor/jundot-oqe/

Slices vendored from oMLX's built-in oQe calibration corpus:

- Source: `omlx/oqe_calibration_data.json` in https://github.com/jundot/omlx
  (fetched 2026-10-10; sha256
  `04d98e2d7367f7a53e3efa759acded87717d8b70562df142e1e02963af571aa0`
  for the full upstream file — identical to the pinned omlx checkout).
- License: Apache License 2.0 (repo LICENSE, no separate data license).
  Reuse complies via this notice; the upstream project is credited in
  `manifest.json` "vendor" alongside the slice list.
- Slices taken (agentic + coding only): `code`, `tool_calling`, `chat`,
  `reasoning` — 1055 texts, ~2.3 MB, ~416k tokens @5.5ch/tok.
- Slices deliberately NOT taken: `ko`, `zh`, `ja` (out of scope by
  decision), `en`, `mixed`, `bartowski` (general mass deferred; can be
  added by extending `SLICES` in `scripts/vendor_oqe_slices.py`).
- Regeneration: `python3 scripts/vendor_oqe_slices.py <oqe json>`.
  Do not hand-edit the `.txt` files; they are build input, not corpus.
