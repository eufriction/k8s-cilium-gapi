# README update rules

Update these sections together so `README.md` stays internally consistent.

## 1. Scenario table

- Mark stable scenario outcomes as `✅ Pass`.
- Use precise notes for branch-only passes or known failures.
- If a formerly failing scenario now passes on the latest branch build, update the status.

## 2. Known Cilium bugs

- Move bugs fixed by merged PRs from **Open bugs** to **Fixed (merged, not yet released)** unless the fix is already released.
- Keep genuinely open issues in **Open bugs**, but update their status if the latest branch run no longer reproduces them.
- Do not claim an issue is fixed upstream solely because one local branch run passed. Prefer wording like `not reproduced by latest branch run` unless the fixing PR is known.

## 3. Test results by version

- Use a branch-build column like `main (<sha>)` for local Cilium branch images based on main.
- If replacing an older branch column such as `main + #44889` after that PR merges, rename it to `main (<sha>)`.
- Add missing scenario rows when scenarios were tested but are absent from the grid.
- Keep result symbols consistent with the legend.

## 4. Legend and run notes

Keep the legend stable and limited to symbol meanings. Do not add volatile run metadata such as SHAs, dates, log paths, or branch names to the legend.

Recommended legend text:

```md
**Legend:** ✅ = scenario passed, ❌ = scenario failed, ⏭️ = intentionally skipped by version guard (known bug or unsupported feature), · = no result recorded.
```

Put volatile run context in column titles and a separate `**Run notes:**` paragraph instead.
