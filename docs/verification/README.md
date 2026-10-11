# Local verification snapshots

Reports copied from the development machine on 2026-10-08 for the initial source publication are historical local results. The separate GitHub Actions trace below proves CI for one source commit; neither local reports nor that CI prove the full Windows/VM acceptance matrix.

- `clear-tests.json`: PowerShell 5.1, 12 checks; only a disposable fixture was trimmed. Worker cancellation/progress queue and WPF terminal states are covered.
- `checkbox-tests.json`: selection, permission persistence, protection and no actions from ticking a checkbox.
- `core-tests.json`: earlier 17-check run including integration fixtures; timestamp identifies the earlier revision.
- `monitor-baseline.json`: four short collector samples, not GUI idle/soak.
- `gui-smoke.json`: earlier offscreen smoke snapshot, 19 controls/394 rows/255.5 MB; predates the current Clear controls. Does not prove the 250 MB GUI target.
- `desktop-shortcut.json`: shortcut COM readback; local paths were redacted for publication. Verified before redaction; the shortcut was not launched by this check.
- `clear-preview.png`: offscreen UI from the Clear test.
- `clear-running-preview.png`, `clear-completed-preview.png`: illustrative UI events, not a full Clear operation on working applications.
- `github-actions-initial.json`: observed successful GitHub Actions run [37747840494](https://github.com/manhdauvn09-manhds/ClearRAM/actions/runs/37747840494) for source commit `a53e87e09d756d9adcedf386e89a54c75c26a77d`, including each step's conclusion. Does not imply later commits or the full acceptance matrix passed.

Current source entry points are in `tests/`. Initial Core/Clear snapshots remain historical; current Disk/Temp/Memory suites write dated reports here and ignored fixture evidence under `artifacts/`. Runtime `.data`, full process inventories, executables, archives and machine-specific harness state are excluded from publication.

The 2026-10-11 portable source checkpoint is summarized in `portable-session-verification.json`:16 local Win11 readiness steps,13 disposable child task checks and6 WPF worker/timer checks. `portable-build.json` records the ZIP manifest/entry hashes and packaged controls/native compilation smoke. These are local results; GitHub Actions for the new source is unproven until an observed run is recorded separately. Child foreground/service/settings/policy providers are synthetic and do not modify real user settings or close user apps. Memory3 remains gated; general app-data deletion and Windows10 acceptance remain unverified.
