# Local verification snapshots

Reports copied from the development machine on 2026-10-08 for the initial source publication. These are historical local results, **not** evidence that GitHub Actions or the full Windows/VM acceptance matrix passed.

- `clear-tests.json`: PowerShell 5.1, 12 checks; only a disposable fixture was trimmed. Worker cancellation/progress queue and WPF terminal states are covered.
- `checkbox-tests.json`: selection, permission persistence, protection and no actions from ticking a checkbox.
- `core-tests.json`: earlier 17-check run including integration fixtures; timestamp identifies the earlier revision.
- `monitor-baseline.json`: four short collector samples, not GUI idle/soak.
- `gui-smoke.json`: earlier offscreen smoke snapshot, 19 controls/394 rows/255.5 MB; predates the current Clear controls. Does not prove the 250 MB GUI target.
- `desktop-shortcut.json`: shortcut COM readback; local paths were redacted for publication. Verified before redaction; the shortcut was not launched by this check.
- `clear-preview.png`: offscreen UI from the Clear test.
- `clear-running-preview.png`, `clear-completed-preview.png`: illustrative UI events, not a full Clear operation on working applications.

Current source entry points are in `tests/`. Tests write new results into ignored `artifacts/`; the snapshots here are not overwritten automatically. Runtime `.data`, full process inventories, executables, archives and machine-specific harness state are excluded from publication.
