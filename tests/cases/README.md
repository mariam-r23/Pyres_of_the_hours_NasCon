# Shared test cases

Both implementations (Python reference and Anosha's GDScript) must pass every case here. Format is
`PROJECT_CONTEXT.md` 6.4, with these clarifications:

- **A file holds a list of cases** (6.4 shows one object; a single object is also fine). Please support both.
- **Level resolution:** `level` is a level id. Look for `<id>.json` in `levels/data/`, then in
  `tests/cases/fixtures/`, then `tests/fixtures/`. Fixtures are tiny rule-test levels. They are NOT in `levels/data/` so that
  `validate_levels` never scans them.
- `actions`: `move:<dir>`, `burn:<dir>`, `interact`, `wait` (dir = up, down, left, right).
- **Runner semantics:** apply actions in order.
  - If `expect.rejected_at` is present: stop at the first rejected action. Its **0-based index** and its `reason`
    must match, and `actions_used` (if present) is the count of valid actions before it.
  - Otherwise any rejection fails the test; after the last action compare `won`, `failed`, `actions_used`.
- `actions_used` = the action counter. Rejected actions never count (invalid actions are free).
- `FX_wrong_ash_unsolvable` is used by solver tests, not by a case file: the solver must report it unsolvable.
- Regenerate with `reference/python/gen_cases.py`. Do not hand-edit these files.
