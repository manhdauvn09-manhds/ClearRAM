#!/usr/bin/env python3
"""`harness handoff` -- the NOW of Handoff.md generated from facts (Harness v3, Dot A, D3).

Nobody copies numbers into a handoff by hand any more: this renders a block from
what can be READ right now -- git HEAD and its CI result, the install receipts of
the fleet, the newest packed bundle, `harness doctor`, the resident daemon -- and
writes it between two markers under `## NOW`. Everything outside the markers is
the person's (NEXT / OPEN / AVOID stay hand-written).

Every value carries WHERE it came from (C13), and a value that cannot be read is
reported as "khong doc duoc" with the reason -- never as a guess and never as
green (C12/C14). "Cannot verify CI from here" is a compliant answer.

handoff.yaml (optional, .harness/schemas/handoff.schema.json): structured OPEN
items whose `until:` is a condition a machine can evaluate. `check` lists the ones
whose condition is now met, so an item retires when its condition is met instead
of hanging for six weeks. Condition kinds:
  manual                       never auto-closed (the default when until is prose)
  file_absent: <rel>           the file no longer exists in the repo
  file_present: <rel>          the file now exists
  git_merged: <ref>            <ref> is an ancestor of HEAD (that branch's work is in here)
  git_pushed: <remote/branch>  HEAD is contained in <remote/branch> and the tree is clean
  ci_green: <sha-prefix>       gh reports a successful completed run for that commit
  receipt_version_min: x.y.z   every fleet receipt is at least this version (toolkit only)

CLI: harness_handoff_gen.py render [ROOT] [--write] [--no-ci] [--no-doctor] [--fleet BASE]
     harness_handoff_gen.py check  [ROOT] [--json]
stdlib only.
"""
import glob
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

BEGIN = "<!-- BEGIN generated-now (harness handoff render) -->"
END = "<!-- END generated-now -->"


# ----------------------------------------------------------------- helpers

def _git(root, *args, timeout=20):
    try:
        p = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, timeout=timeout,
                           encoding="utf-8", errors="replace")
        return (p.stdout or "").strip() if p.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def _load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _semver(s):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", str(s or ""))
    return tuple(int(x) for x in m.groups()) if m else None


# ----------------------------------------------------------------- facts

def fact_git(root):
    head = _git(root, "rev-parse", "HEAD")
    if not head:
        return {"ok": False, "source": "git rev-parse HEAD", "why": "not a git repo or git unreadable"}
    branch = _git(root, "rev-parse", "--abbrev-ref", "HEAD") or "?"
    date = _git(root, "log", "-1", "--format=%ci") or "?"
    subject = _git(root, "log", "-1", "--format=%s") or ""
    st = _git(root, "status", "--porcelain")
    dirty = len([l for l in (st or "").splitlines() if l.strip()])
    ahead = _git(root, "rev-list", "--count", "@{u}..HEAD")
    return {"ok": True, "source": "git", "head": head, "short": head[:8], "branch": branch, "date": date[:16],
            "subject": subject[:80], "dirty": dirty, "ahead": (int(ahead) if ahead and ahead.isdigit() else None)}


def fact_ci(root, sha):
    """CI result for THIS commit, four honest states (same vocabulary as harness doctor)."""
    gh = shutil.which("gh")
    if not gh:
        return {"state": "unknown", "source": "gh", "detail": "gh is not installed -- cannot verify CI from here"}
    try:
        p = subprocess.run([gh, "run", "list", "--commit", sha, "--limit", "10",
                            "--json", "conclusion,status,name,createdAt,workflowName"],
                           cwd=root, capture_output=True, text=True, timeout=10, encoding="utf-8", errors="replace")
    except Exception as e:  # noqa: BLE001
        return {"state": "unknown", "source": "gh run list --commit", "detail": "gh call failed (%s)" % e}
    if p.returncode != 0:
        err = (p.stderr or "").strip().splitlines()
        msg = err[-1] if err else "exit %d" % p.returncode
        if "404" in msg or "not found" in msg.lower() or "Could not resolve" in msg:
            msg += " -- often the wrong `gh` account is active for this repo (gh auth status)"
        return {"state": "unknown", "source": "gh run list --commit", "detail": msg}
    try:
        runs = json.loads(p.stdout or "[]")
    except ValueError:
        return {"state": "unknown", "source": "gh", "detail": "gh returned non-JSON"}
    if not runs:
        return {"state": "none", "source": "gh run list --commit %s" % sha[:8], "detail": "no workflow run for this commit (not pushed, or CI did not trigger)"}
    names = []
    worst = "pass"
    for r in runs:
        n = r.get("workflowName") or r.get("name") or "?"
        if r.get("status") != "completed":
            names.append("%s: %s" % (n, r.get("status")))
            worst = "unknown" if worst == "pass" else worst
        elif r.get("conclusion") == "success":
            names.append("%s: success" % n)
        else:
            names.append("%s: %s" % (n, r.get("conclusion")))
            worst = "fail"
    return {"state": worst, "source": "gh run list --commit %s" % sha[:8], "detail": "; ".join(names)}


def fact_bundle(root):
    d = os.path.join(root, "bundles", "standard-governance")
    if not os.path.isdir(d):
        return None
    best = None
    for f in glob.glob(os.path.join(d, "standard-governance-*.bundle.json")):
        m = re.search(r"standard-governance-(\d+\.\d+\.\d+)\.bundle\.json$", f)
        if m and (best is None or _semver(m.group(1)) > _semver(best[0])):
            best = (m.group(1), f)
    if not best:
        return None
    out = {"version": best[0], "file": os.path.basename(best[1]), "source": "bundles/standard-governance/*.bundle.json"}
    try:
        with open(best[1], encoding="utf-8-sig") as f:
            j = json.load(f)
        out["files"] = len(j.get("files") or [])
        out["content_hash"] = str(j.get("content_hash") or "")[:8]
    except Exception:  # noqa: BLE001
        pass
    return out


def fact_fleet(root, base):
    """Install receipts of every checkout under `base` (toolkit only: needs set_model_ladder.discover)."""
    disc = os.path.join(root, "tools", "harness-bundle", "set_model_ladder.py")
    if not base or not os.path.isfile(disc):
        return None
    try:
        mod = _load_module(disc, "set_model_ladder")
        projects = mod.discover(base)
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "source": disc, "why": str(e)}
    rows = []
    for p in projects:
        rec = os.path.join(p, ".harness", ".bundle-manifest.json")
        label = os.path.relpath(p, base.split(";")[0]).replace("\\", "/") if p.lower().startswith(base.split(";")[0].lower()) else p
        try:
            with open(rec, encoding="utf-8-sig") as f:
                j = json.load(f)
            rows.append({"label": label, "version": str(j.get("version") or "?"), "status": str(j.get("status") or "?"),
                         "installed_at": str(j.get("installed_at") or "")[:10]})
        except Exception:  # noqa: BLE001
            rows.append({"label": label, "version": "-", "status": "no receipt", "installed_at": ""})
    return {"ok": True, "source": "%s (discover) + .harness/.bundle-manifest.json" % os.path.basename(disc), "base": base, "rows": rows}


def fact_doctor(root):
    try:
        import harness_doctor as hd
        counts = {hd.OK: 0, hd.WARN: 0, hd.FAIL: 0, hd.INFO: 0}
        fails, warns = [], []
        for status, label, detail in hd.run(root):
            counts[status] += 1
            if status == hd.FAIL:
                fails.append(label)
            elif status == hd.WARN:
                warns.append(label)
        return {"ok": True, "source": "harness_doctor.run", "ok_n": counts[hd.OK], "warn": counts[hd.WARN],
                "fail": counts[hd.FAIL], "fails": fails, "warns": warns}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "source": "harness_doctor.run", "why": "%s: %s" % (type(e).__name__, e)}


def fact_daemon(root):
    try:
        import harnessd
        port = harnessd.daemon_config(root)["port"]
        h = harnessd.health(port, 1.0)
        if not h:
            return {"ok": False, "source": "GET 127.0.0.1:%d/health" % port, "why": "not running"}
        return {"ok": True, "source": "GET 127.0.0.1:%d/health" % port, "pid": h.get("pid"), "version": h.get("version"),
                "pre_p95_ms": h.get("pre_p95_ms"), "pre": (h.get("counts") or {}).get("pre"),
                "ledger_written": h.get("ledger_written"), "ledger_failed": h.get("ledger_failed"), "uptime_s": h.get("uptime_s")}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "source": "harnessd", "why": str(e)}


def server_ci_detail(s):
    """One line for a server CI summary. Counts only jobs whose status IS "pass" and names the
    rest: a job the server cannot run (installer-windows-ps51 is "not-runnable-here") is not a
    pass, and counting every job read 14 green where 13 ran (C12/C14, 17-11)."""
    jobs = s.get("jobs") or {}
    status = {n: (r.get("status") if isinstance(r, dict) else None) for n, r in jobs.items()}
    if s.get("verdict") != "pass":
        return "FAILED: " + ", ".join(sorted(n for n, st in status.items() if st == "fail"))
    passed = sum(1 for st in status.values() if st == "pass")
    other = sorted("%s=%s" % (n, st or "?") for n, st in status.items() if st != "pass")
    return "%d job pass" % passed + (" (không tính: %s)" % ", ".join(other) if other else "")


def gather(root, ci=True, doctor=True, fleet_base=""):
    g = fact_git(root)
    facts = {"generated_at": datetime.now().astimezone().strftime("%Y-%m-%d %H:%M"), "root": root, "git": g}
    facts["ci"] = fact_ci(root, g["head"]) if (ci and g.get("ok")) else {"state": "skipped", "source": "--no-ci", "detail": "not asked"}
    if facts["ci"]["state"] in ("fail", "none", "unknown"):
        # GitHub cannot vouch for HEAD: the server-side run for this exact commit may (12-11).
        try:
            import harness_doctor as hd
            s = hd._ci_server_summary(root)
        except Exception:  # noqa: BLE001
            s = None
        if s:
            facts["ci"] = {"state": "pass" if s.get("verdict") == "pass" else "fail",
                           "source": "%s (server CI on %s; GitHub: %s)" % (s["_path"], s.get("host", "?"), facts["ci"]["detail"]),
                           "detail": server_ci_detail(s)}
    facts["bundle"] = fact_bundle(root)
    facts["fleet"] = fact_fleet(root, fleet_base) if fleet_base else None
    facts["doctor"] = fact_doctor(root) if doctor else None
    facts["daemon"] = fact_daemon(root)
    facts["open_items"] = check_items(root)
    facts["open_met"] = [i for i in facts["open_items"] if i["met"] is True]
    return facts


# ----------------------------------------------------------------- render

def render(facts):
    L = [BEGIN, "**Sinh tự động %s** (`harness-handoff-render`; mỗi dòng ghi nguồn — C13; không đọc được thì nói, không đoán — C12/C14):" % facts["generated_at"], ""]
    g = facts["git"]
    if g.get("ok"):
        extra = []
        if g["dirty"]:
            extra.append("%d file chưa commit" % g["dirty"])
        if g.get("ahead"):
            extra.append("%d commit chưa push" % g["ahead"])
        L.append("- **Git:** `%s` trên `%s` (%s) — %s%s · nguồn: git" % (g["short"], g["branch"], g["date"], g["subject"],
                                                                      (" · " + ", ".join(extra)) if extra else ""))
    else:
        L.append("- **Git:** không đọc được (%s) · nguồn: %s" % (g.get("why"), g.get("source")))
    c = facts["ci"]
    word = {"pass": "XANH", "fail": "ĐỎ", "none": "chưa có run", "unknown": "KHÔNG KIỂM ĐƯỢC từ đây", "skipped": "không hỏi"}[c["state"]]
    L.append("- **CI của HEAD:** %s — %s · nguồn: %s" % (word, c["detail"], c["source"]))
    b = facts.get("bundle")
    if b:
        L.append("- **Bundle mới nhất đã pack:** %s (%s file, hash `%s…`) · nguồn: %s" % (b["version"], b.get("files", "?"), b.get("content_hash", "?"), b["source"]))
    f = facts.get("fleet")
    if f and f.get("ok"):
        rows = f["rows"]
        by = {}
        for r in rows:
            by.setdefault((r["version"], r["status"]), []).append(r["label"])
        parts = ["%d × %s %s" % (len(v), k[0], k[1]) for k, v in sorted(by.items(), key=lambda kv: (-len(kv[1]), kv[0]))]
        L.append("- **Fleet dưới `%s`:** %d checkout — %s · nguồn: %s" % (f["base"], len(rows), "; ".join(parts), f["source"]))
        newest = (facts.get("bundle") or {}).get("version")
        odd = [r for r in rows if r["status"] != "complete" or (newest and r["version"] != newest)]
        for r in odd:
            L.append("  - `%s`: %s %s%s" % (r["label"], r["version"], r["status"],
                                              (" (bundle mới nhất %s)" % newest if newest and r["version"] != newest else "")))
    elif f:
        L.append("- **Fleet:** không đọc được (%s) · nguồn: %s" % (f.get("why"), f.get("source")))
    d = facts.get("doctor")
    if d and d.get("ok"):
        tail = ""
        if d["fails"]:
            tail += " — FAIL: " + ", ".join(d["fails"])
        if d["warns"]:
            tail += " — WARN: " + ", ".join(d["warns"])
        L.append("- **Doctor:** %d OK, %d WARN, %d FAIL%s · nguồn: %s" % (d["ok_n"], d["warn"], d["fail"], tail, d["source"]))
    elif d:
        L.append("- **Doctor:** không chạy được (%s)" % d.get("why"))
    dm = facts["daemon"]
    if dm.get("ok"):
        L.append("- **harnessd:** chạy pid %s v%s, %s request pre, p95 %s ms, ledger %s ghi / %s lỗi, uptime %ss · nguồn: %s"
                 % (dm["pid"], dm["version"], dm["pre"], dm["pre_p95_ms"], dm["ledger_written"], dm["ledger_failed"], dm["uptime_s"], dm["source"]))
    else:
        L.append("- **harnessd:** KHÔNG chạy (%s) — hook http đang fail-open tới prompt kế · nguồn: %s" % (dm.get("why"), dm.get("source")))
    if facts.get("open_met"):
        L.append("- **OPEN đã thoả `until:` (handoff.yaml) — xoá được:** " + ", ".join("`%s`" % i["id"] for i in facts["open_met"]))
    items = facts.get("open_items") or []
    if items:
        n_met = sum(1 for i in items if i["met"] is True)
        n_auto = sum(1 for i in items if i["until"] != "manual")
        L.append("- **OPEN (handoff.yaml): %d mục, %d máy kiểm được, %d đã thoả.** Mỗi dòng: id · từ ngày · điều kiện gỡ." % (len(items), n_auto, n_met))
        for i in items:
            tag = {True: "MET", False: "chờ", None: "tay"}[i["met"]]
            cond = i["until"] if i["until"] != "manual" else (i.get("until_note") or "manual")
            L.append("  - [%s] `%s` · %s · %s" % (tag, i["id"], i.get("since") or "?", cond[:160]))
    L.append(END)
    return "\n".join(L)


def write_block(handoff_path, block):
    """Replace the marker block, or insert it right under `## NOW`. Returns (changed, text)."""
    try:
        with open(handoff_path, encoding="utf-8-sig") as f:
            text = f.read()
    except OSError:
        text = "# Handoff\n\n## NOW\n\n## NEXT\n\n## OPEN\n\n## AVOID\n"
    if BEGIN in text and END in text:
        a = text.index(BEGIN)
        b = text.index(END) + len(END)
        new = text[:a] + block + text[b:]
    else:
        m = re.search(r"^## NOW[^\n]*\n", text, re.M)
        if m:
            new = text[:m.end()] + "\n" + block + "\n" + text[m.end():]
        else:
            new = text.rstrip("\n") + "\n\n## NOW\n\n" + block + "\n"
    changed = new != text
    if changed:
        with open(handoff_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(new)
    return changed, new


# ----------------------------------------------------------------- handoff.yaml `until:`

def _yaml_items(path):
    """Minimal reader for the `open:` list of handoff.yaml (no PyYAML in a hook)."""
    try:
        with open(path, encoding="utf-8-sig") as f:
            lines = f.read().splitlines()
    except OSError:
        return []
    items, cur, inside = [], None, False
    for raw in lines:
        if re.match(r"^open\s*:\s*$", raw):
            inside = True
            continue
        if inside and raw and not raw.startswith((" ", "\t", "-")):
            break
        if not inside:
            continue
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        m = re.match(r"^-\s+(\w+)\s*:\s*(.*)$", s)
        if m:
            if cur:
                items.append(cur)
            cur = {m.group(1): _val(m.group(2))}
            continue
        m = re.match(r"^(\w+)\s*:\s*(.*)$", s)
        if m and cur is not None:
            cur[m.group(1)] = _val(m.group(2))
    if cur:
        items.append(cur)
    return items


def _val(v):
    v = v.strip()
    if v[:1] in ("'", '"') and v[-1:] == v[:1]:
        return v[1:-1]
    return v


def evaluate_until(root, cond, fleet_base=""):
    """-> (met: True|False|None, detail). None = cannot evaluate (manual / unreadable)."""
    cond = str(cond or "").strip()
    if not cond or cond == "manual":
        return None, "manual"
    kind, _, arg = cond.partition(":")
    kind, arg = kind.strip(), arg.strip()
    if kind == "file_absent":
        return (not os.path.exists(os.path.join(root, arg))), "file_absent %s" % arg
    if kind == "file_present":
        return os.path.exists(os.path.join(root, arg)), "file_present %s" % arg
    if kind == "git_merged":
        head = _git(root, "rev-parse", "HEAD")
        if not head:
            return None, "git unreadable"
        try:
            p = subprocess.run(["git", "-C", root, "merge-base", "--is-ancestor", arg, "HEAD"], capture_output=True, timeout=20)
        except (OSError, subprocess.SubprocessError):
            return None, "git unreadable"
        if p.returncode == 0:
            return True, "git_merged %s" % arg
        if p.returncode == 1:
            return False, "git_merged %s" % arg
        return None, "git_merged %s: ref not found" % arg
    if kind == "git_pushed":
        # HEAD is contained in <remote-branch> and the tree is clean: "this work is on the remote".
        head = _git(root, "rev-parse", "HEAD")
        if not head:
            return None, "git unreadable"
        try:
            p = subprocess.run(["git", "-C", root, "merge-base", "--is-ancestor", "HEAD", arg], capture_output=True, timeout=20)
        except (OSError, subprocess.SubprocessError):
            return None, "git unreadable"
        if p.returncode not in (0, 1):
            return None, "git_pushed %s: ref not found" % arg
        dirty = len([l for l in (_git(root, "status", "--porcelain") or "").splitlines() if l.strip()])
        if p.returncode == 0 and dirty == 0:
            return True, "HEAD on %s, tree clean" % arg
        return False, ("HEAD not on %s" % arg if p.returncode == 1 else "%d file(s) uncommitted" % dirty)
    if kind == "ci_green":
        c = fact_ci(root, arg)
        if c["state"] == "pass":
            return True, c["detail"]
        if c["state"] in ("fail", "none"):
            return False, c["detail"]
        return None, c["detail"]
    if kind == "receipt_version_min":
        f = fact_fleet(root, fleet_base)
        if not f or not f.get("ok"):
            return None, "fleet not readable"
        want = _semver(arg)
        bad = [r["label"] for r in f["rows"] if not _semver(r["version"]) or _semver(r["version"]) < want]
        return (not bad), ("all >= %s" % arg if not bad else "below %s: %s" % (arg, ", ".join(bad)))
    return None, "unknown condition kind '%s'" % kind


def check_items(root, fleet_base=""):
    out = []
    for it in _yaml_items(os.path.join(root, "handoff.yaml")):
        met, detail = evaluate_until(root, it.get("until", "manual"), fleet_base)
        out.append({"id": it.get("id", "?"), "until": it.get("until", "manual"), "met": met, "detail": detail,
                    "text": it.get("text", ""), "since": it.get("since", ""), "until_note": it.get("until_note", "")})
    return out


# ----------------------------------------------------------------- CLI

def main(argv):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:  # noqa: BLE001
        pass
    args = argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd = args[0]
    root = "."
    opts = {"write": False, "ci": True, "doctor": True, "fleet": "", "json": False}
    i = 1
    while i < len(args):
        a = args[i]
        if a == "--write":
            opts["write"] = True
        elif a == "--no-ci":
            opts["ci"] = False
        elif a == "--no-doctor":
            opts["doctor"] = False
        elif a == "--json":
            opts["json"] = True
        elif a == "--fleet" and i + 1 < len(args):
            opts["fleet"] = args[i + 1]
            i += 1
        elif not a.startswith("-"):
            root = a
        i += 1
    root = os.path.abspath(root)
    if cmd == "render":
        facts = gather(root, ci=opts["ci"], doctor=opts["doctor"], fleet_base=opts["fleet"])
        block = render(facts)
        if opts["json"]:
            print(json.dumps(facts, ensure_ascii=False, indent=1, default=str))
            return 0
        if opts["write"]:
            changed, _ = write_block(os.path.join(root, "Handoff.md"), block)
            print("[handoff] %s Handoff.md (%s)" % ("updated" if changed else "unchanged", facts["generated_at"]))
        else:
            print(block)
        return 0
    if cmd == "check":
        items = check_items(root, opts["fleet"])
        if opts["json"]:
            print(json.dumps(items, ensure_ascii=False, indent=1))
            return 0
        if not items:
            print("[handoff] handoff.yaml has no open: items")
            return 0
        for it in items:
            tag = {True: "MET  ", False: "open ", None: "?    "}[it["met"]]
            print("%s %-28s until: %-40s %s" % (tag, it["id"], it["until"], it["detail"]))
        return 0
    print("usage: harness_handoff_gen.py render|check [ROOT] [--write] [--no-ci] [--no-doctor] [--fleet BASE] [--json]")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
