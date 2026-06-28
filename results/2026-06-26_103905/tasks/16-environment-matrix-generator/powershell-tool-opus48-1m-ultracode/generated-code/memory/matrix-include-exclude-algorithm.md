---
name: matrix-include-exclude-algorithm
description: GitHub Actions strategy.matrix include/exclude expansion semantics (verified against docs)
metadata:
  type: reference
---

GitHub Actions `strategy.matrix` expansion order (matches the official docs fruit/animal example):

1. **Cartesian product** of the axes. The FIRST declared axis varies slowest (outermost loop); the LAST varies fastest. e.g. axes `os,node` → os/18, os/20, win/18, win/20.
2. **exclude**: each entry removes every combination it *partially* matches — a combination is dropped if all keys present in the exclude entry equal the combination's values. So `{os: macos}` removes all macos rows.
3. **include** (applied after exclude, entries processed in order): each entry is merged into every ORIGINAL post-exclude combination it is *compatible* with. Compatible = none of the entry's keys that are ORIGINAL AXIS keys overwrite that combination's value. Original axis values are protected; added (non-axis) keys MAY be overwritten by a later include. An include compatible with NO original combination is appended as a new standalone job. Includes never extend combinations created by other includes.

Key subtlety that trips people up: include compatibility only protects the ORIGINAL axis keys, so `{color: pink, animal: cat}` can overwrite a `color` previously added by `{color: green}` on the cat rows.

Output for a dynamic matrix: emit `{ "include": [ ...combos... ] }` (an include-only matrix is valid) and consume downstream with `matrix: ${{ fromJSON(needs.<job>.outputs.matrix) }}`. GitHub's hard cap is 256 jobs. Implemented in this repo's `BuildMatrix.psm1` (`Get-BuildMatrix`). [[task-16-environment-matrix-generator]]
