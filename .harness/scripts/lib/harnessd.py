#!/usr/bin/env python3
"""harnessd -- the resident harness daemon (Harness v3, Dot A).

Serves Claude Code `type: "http"` hooks on 127.0.0.1:<port> so that NO process is
spawned per tool call (the command hooks cost 970-1290 ms and 60-95 MB of
PowerShell each, twice per call -- measured 12-11-2026):

  POST /hook/pre-tool-use   same verdict as harness-runtime-guard.ps1 / .sh:
                            H4 command deny patterns, C16 worktree budget, C3/C6
                            tool-registry deny-by-default, server PDP consult, F2
                            sensitivity. Every rule is READ from the project's own
                            control files (C2); nothing is hardcoded here.
  POST /hook/post-tool-use  tool-calls.log, ledger entry (queued, ONE writer),
                            qa-gate (casan-policies governance.qa_gate).
  GET  /health              {ok, version, pid, uptime_s, p50_ms, p95_ms, ...}
  POST /shutdown           needs X-Harnessd-Admin = the secret in <state>/harnessd/admin-<port>.token (H2)

One daemon per machine and user serves every project: the harness root is found
from the `cwd` of each hook payload. Policy files are cached per root and reloaded
when their mtime changes.

Ledger writes use the SAME byte-range lock on .harness/ledger/chain.lock as
evidence-ledger.ps1 / .sh, and the bash writer's hash rule (sorted-key compact
JSON), so both existing verifiers accept the entries (B-87 rule).

Honest scope (C10): a local daemon is defense-in-depth. When it is down, Claude
Code's http hook fails per settings.json `onFailure` (default: continue = the
tool call proceeds unguarded until `harnessd ensure` runs at the next prompt).
Every request leaves one line in harnessd.log (C12).

Reload without a gap (Dot B, B-99): when a lib file changes on disk the running
daemon starts the NEW one on its own listening socket (Windows: socket.share,
POSIX: fd inheritance), waits until the new one serves, then stops accepting.
The port is never empty, so no hook request is refused in between. If the new
code cannot start, the old one keeps serving and says so in hook-errors.log.

CLI: harnessd.py serve|start|ensure|stop|status|bench|guard [--home <root>] [--port N]
stdlib only.
"""
import hashlib
import hmac
import json
import os
import random
import re
import socket
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from queue import Empty, Full, Queue
import urllib.error
import urllib.request

VERSION = "0.3.3"   # 0.3.3 (23-11): H1 policy root from the granted folder, H2 /shutdown secret + no browser requests
HANDOVER_WAIT_S = 20.0
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import harness_checkout_facts as facts          # noqa: E402
import harness_sensitivity as sens              # noqa: E402
import harness_worktree as wt                   # noqa: E402
import harness_write_scope as wscope            # noqa: E402  C17
from harness_handoff import read_config         # noqa: E402

GUARD = "harness-runtime-guard"   # the name the deny texts have always carried

DEFAULTS = {
    "enabled": True,
    "port": 47631,
    "idle_exit_minutes": 480,
    "pre_tool_use_timeout_s": 20,
    "on_failure": "continue",
    "ledger_queue_max": 10000,
}

# PDP pre-filter shapes, VERBATIM from harness-runtime-guard.ps1 (kept broad on
# purpose: the mention-vs-invocation rule lives server-side in app/core/pdp.py).
_HR1 = re.compile(r"\b(curl|wget|Invoke-WebRequest|iwr|nc|ncat|http_fetch|deploy|drop\s+table|"
                  r"truncate\s+table|delete\s+from|alter\s+table)\b", re.IGNORECASE)
_HR2 = re.compile(r"\bdocker[-\s]+compose\b", re.IGNORECASE)
_HR3 = re.compile(r"(deploy|release|\bkubectl\s+apply\b|\bhelm\s+(install|upgrade)\b|"
                  r"\bterraform\s+apply\b|\bansible-playbook\b)", re.IGNORECASE)
_HR_TOOLS = {"deploy", "rollback_deploy", "mysql_query", "exec_in_container", "http_fetch"}
_WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
_MCP = re.compile(r"^mcp__(.+?)__(.+)$")


# ----------------------------------------------------------------- small utils

def now_iso():
    return datetime.now().astimezone().isoformat()


def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256(s):
    return hashlib.sha256((s or "").encode("utf-8")).hexdigest()


def append_line(path, line):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8", newline="\n") as f:
        f.write(line + "\n")


def state_dir():
    d = os.path.join(facts._state_dir(), "harnessd")
    os.makedirs(d, exist_ok=True)
    return d


def state_path():
    return os.path.join(state_dir(), "state.json")


def read_state():
    try:
        with open(state_path(), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def daemon_config(root):
    cfg = dict(DEFAULTS)
    try:
        cfg.update({k: v for k, v in (read_config(root, "daemon") or {}).items() if v is not None})
    except Exception:  # noqa: BLE001
        pass
    return cfg


def find_root(start):
    """The nearest ancestor (or `start` itself) holding a .harness directory, else None."""
    if not start:
        return None
    p = os.path.abspath(start)
    for _ in range(40):
        if os.path.isdir(os.path.join(p, ".harness")):
            return p
        parent = os.path.dirname(p)
        if parent == p:
            return None
        p = parent
    return None


_POLICY_FILES = ("risk-policy.yaml", "tool-registry.json")


def find_policy_root(start):
    """The nearest ancestor (or `start`) whose .harness/control holds the policy files, else None.
    H1 (23-11): a bare `.harness` directory is not a policy root -- `mkdir x/.harness && cd x`
    used to make the daemon read policy from x, find nothing, and allow everything."""
    if not start:
        return None
    p = os.path.abspath(start)
    for _ in range(40):
        ctl = os.path.join(p, ".harness", "control")
        if all(os.path.isfile(os.path.join(ctl, n)) for n in _POLICY_FILES):
            return p
        parent = os.path.dirname(p)
        if parent == p:
            return None
        p = parent
    return None


def policy_root(payload, home=None):
    """Which project's policy judges this hook payload (H1, 23-11).

    1. The folder the session was GRANTED, read from the transcript path (Claude Code writes it
       under ~/.claude/projects/<key of the folder it was opened on>) -- the same source C17 uses.
       `cwd` cannot move a session out of it: cd-ing into a subfolder, or into another project,
       never swaps the policy that judges the session.
    2. No transcript (another caller, the cold path): the nearest ancestor of `cwd` that holds
       the policy files -- never a bare `.harness`.
    3. HARNESS_ROOT, then the daemon's home.
    Honest scope (C10): the transcript path is in the payload Claude Code sends; a caller that
    forges payloads can name any root. That caller is already past the hook."""
    cwd = payload.get("cwd") or ""
    try:
        groot, src = wscope.granted_root(payload, find_root(cwd))
    except Exception:  # noqa: BLE001 -- fall through to the cwd rule
        groot, src = None, ""
    if groot and str(src).startswith("transcript"):
        g = find_policy_root(groot)
        if g:
            return g
    return (find_policy_root(cwd) or find_policy_root(os.environ.get("HARNESS_ROOT") or "")
            or home or find_root(cwd))


def registry_candidates(name, tools):
    """Registry keys to try for a tool name, most precise first (see guard .ps1)."""
    c = [name]
    m = _MCP.match(name or "")
    if m:
        server, short = m.group(1), m.group(2)
        c.append("%s.%s" % (server, short))
        c.append(short)
        suffix = "." + short
        c.extend(k for k in (tools or {}) if k.endswith(suffix) and k not in c)
    return c


def short_tool(name):
    m = _MCP.match(name or "")
    return m.group(2) if m else (name or "")


# ----------------------------------------------------------------- policy cache

class RootPolicy:
    """Everything the guard reads for one harness root, reloaded on mtime change."""

    def __init__(self, root):
        self.root = root
        self.H = os.path.join(root, ".harness")
        self._cache = {}
        self._lock = threading.Lock()

    def _cached(self, key, path, loader):
        try:
            m = os.path.getmtime(path)
        except OSError:
            m = None
        with self._lock:
            hit = self._cache.get(key)
            if hit and hit[0] == m:
                return hit[1]
        try:
            val = loader(path) if m is not None else None
        except Exception:  # noqa: BLE001 -- a broken policy file never bricks the shell
            val = None
        with self._lock:
            self._cache[key] = (m, val)
        return val

    def deny_patterns(self):
        def load(p):
            pats = []
            with open(p, encoding="utf-8-sig") as f:
                for line in f.read().split("\n"):
                    m = re.match(r'^-\s+pattern:\s+"(.+)"$', line.strip())
                    if m:
                        pat = m.group(1).replace("\\\\", "\\")
                        try:
                            pats.append((pat, re.compile(pat)))
                        except re.error:
                            continue  # fail-open per pattern, the rest still enforce
            return pats
        return self._cached("deny", os.path.join(self.H, "control", "risk-policy.yaml"), load) or []

    def registry(self):
        def load(p):
            with open(p, encoding="utf-8-sig") as f:
                return (json.load(f) or {}).get("tools") or {}
        return self._cached("registry", os.path.join(self.H, "control", "tool-registry.json"), load) or {}

    def sensitive(self):
        def load(p):
            cfg, rules, err = sens.load_rules(self.root)
            if err or not cfg:
                return None
            return {"cfg": cfg, "rules": rules, "tiers": sens.load_tiers(self.root),
                    "enforce": cfg.get("enforce_at_pretooluse") is True}
        return self._cached("sens", os.path.join(self.H, "control", "sensitive-paths.json"), load)

    def tool_overrides(self):
        """{registry key: override} from .harness/project/tool-overrides.json -- the owner's
        per-project decision to turn a deny-by-default tool into ASK (never allow). The
        file is project-owned: bundle installs never ship or overwrite .harness/project/,
        so the decision survives updates (it was reset by every install before, 15-11).
        An entry is honoured only when it is complete -- action "ask", a reason, who
        approved it, when -- and not past `expires_on`; anything else is ignored and the
        registry's deny stands (fail-closed for the relaxation, C10/C14)."""
        def load(p):
            with open(p, encoding="utf-8-sig") as f:
                doc = json.load(f) or {}
            out = {}
            for e in doc.get("overrides") or []:
                if not isinstance(e, dict):
                    continue
                key = str(e.get("tool") or "").strip()
                if not key or e.get("action") != "ask":
                    continue
                if not all(str(e.get(k) or "").strip() for k in ("reason", "approved_by", "approved_on")):
                    continue
                exp = str(e.get("expires_on") or "").strip()
                if exp and exp < time.strftime("%Y-%m-%d"):
                    continue
                out[key] = e
            return out
        return self._cached("overrides", os.path.join(self.H, "project", "tool-overrides.json"), load) or {}

    def sync(self):
        """(sync_root, cfg) -- portal-sync.json, resolved through git for a worktree (C13)."""
        sync_root = self.root
        if not os.path.isfile(os.path.join(self.H, "portal-sync.json")):
            parent = facts.parent_of_worktree(self.root)
            if parent:
                sync_root = parent
        p = os.path.join(sync_root, ".harness", "portal-sync.json")

        def load(path):
            with open(path, encoding="utf-8-sig") as f:
                return json.load(f) or {}
        return sync_root, (self._cached("sync:" + sync_root, p, load) or {})

    def qa_gate(self):
        """(enabled, blocking_tools) from governance.qa_gate -- same narrow scan as the .ps1."""
        def load(p):
            enabled, blocking, inside = False, [], False
            with open(p, encoding="utf-8-sig") as f:
                for line in f:
                    line = line.rstrip("\r\n")
                    if re.match(r"^\s{2}qa_gate:\s*$", line):
                        inside = True
                        continue
                    if inside:
                        if line.strip() and not re.match(r"^\s{4}", line):
                            inside = False
                            continue
                        m = re.match(r"^\s{4}enabled:\s*(\S+)", line)
                        if m:
                            enabled = m.group(1).lower() in ("true", "yes", "1")
                        m = re.match(r'^\s{6}-\s*"?([A-Za-z0-9_.\-]+)"?', line)
                        if m:
                            blocking.append(m.group(1))
            return enabled, blocking
        return self._cached("qa", os.path.join(self.H, "control", "casan-policies.yaml"), load) or (False, [])

    def qa_verdict(self):
        verdict, vpath = "", "artifacts/qa-gate/<pipeline_id>-verdict.md"
        p = os.path.join(self.H, "context", "pipeline-context.yaml")
        try:
            with open(p, encoding="utf-8-sig") as f:
                for line in f:
                    m = re.match(r'^\s*qa_gate_verdict:\s*"?([A-Za-z_]+)"?', line)
                    if m and not verdict:
                        verdict = m.group(1)
                    m = re.match(r'^\s*qa_gate_verdict_path:\s*"?([^"\r\n]+)"?', line)
                    if m:
                        vpath = m.group(1).strip()
        except OSError:
            pass
        return verdict, vpath


_policies = {}
_policies_lock = threading.Lock()


def policy_for(root):
    with _policies_lock:
        p = _policies.get(root)
        if p is None:
            p = _policies[root] = RootPolicy(root)
        return p


# ----------------------------------------------------------------- evidence sinks

def hook_error(root, msg):
    try:
        append_line(os.path.join(root, ".harness", "telemetry", "hook-errors.log"),
                    json.dumps({"timestamp": now_iso(), "hook": "harnessd", "error": msg[:400]}))
    except Exception:  # noqa: BLE001
        pass


def security_event(root, payload, ev_type, severity, category, excerpt):
    try:
        ev = {"event_id": str(uuid.uuid4()), "timestamp": now_iso(), "type": ev_type,
              "severity": severity, "category": category, "detected_by": GUARD,
              "excerpt": excerpt, "session_id": payload.get("session_id") or os.environ.get("HARNESS_SESSION_ID", ""),
              "actor_user": os.environ.get("HARNESS_USER", "")}
        append_line(os.path.join(root, ".harness", "telemetry", "security-events.jsonl"),
                    json.dumps(ev, ensure_ascii=False))
    except Exception as e:  # noqa: BLE001
        hook_error(root, "security event not written: %s" % e)


def _actor(payload, agent="claude-code"):
    return {"agent": agent, "user": os.environ.get("HARNESS_USER", ""),
            "session_id": payload.get("session_id") or os.environ.get("HARNESS_SESSION_ID", ""),
            "role": "member"}


# ----------------------------------------------------------------- ledger writer

LOCK_TIMEOUT_S = 30.0


def _ledger_lock(ledger_dir):
    """Byte-range lock on byte 0 of chain.lock -- the primitive both shipped writers use."""
    os.makedirs(ledger_dir, exist_ok=True)
    f = open(os.path.join(ledger_dir, "chain.lock"), "a+b")
    deadline = time.time() + LOCK_TIMEOUT_S
    tries = 0
    while True:
        try:
            if os.name == "nt":
                import msvcrt
                f.seek(0)
                msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.lockf(f, fcntl.LOCK_EX | fcntl.LOCK_NB, 1, 0)
            return f
        except OSError:
            if time.time() >= deadline:
                f.close()
                raise TimeoutError("ledger lock not acquired within %ss (another append is holding it)" % LOCK_TIMEOUT_S)
            tries += 1
            hi = min(0.05 * 2 ** (tries // 10), 0.4)
            time.sleep(random.uniform(hi / 4, hi))


def _ledger_unlock(f):
    try:
        if os.name == "nt":
            import msvcrt
            f.seek(0)
            msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            fcntl.lockf(f, fcntl.LOCK_UN, 1, 0)
    finally:
        f.close()


def _last_link(chain_file):
    """(prev_hash, next_index); UNREADABLE (never GENESIS) when the tail cannot be parsed."""
    if not os.path.exists(chain_file) or os.path.getsize(chain_file) == 0:
        return "GENESIS", 0
    n = 0
    with open(chain_file, "rb") as f:
        for line in f:
            if line.strip():
                n += 1
    with open(chain_file, "rb") as f:
        size = os.path.getsize(chain_file)
        window = 64 * 1024
        while True:
            take = min(window, size)
            f.seek(size - take)
            buf = f.read(take).rstrip(b"\r\n")
            nl = buf.rfind(b"\n")
            if nl >= 0 or take >= size or take >= 4 * 1024 * 1024:
                break
            window = min(window * 2, 4 * 1024 * 1024)
    last = buf[nl + 1:].decode("utf-8", "replace")
    h = None
    try:
        h = json.loads(last).get("entry_hash")
    except ValueError:
        m = re.findall(r"\"entry_hash\"\s*:\s*\"([0-9a-fA-F]{64})\"", last)
        h = m[-1] if m else None
    return (h or "UNREADABLE"), n


def entry_hash(e):
    c = dict(e)
    c["entry_hash"] = ""
    return hashlib.sha256(json.dumps(c, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def append_entry(root, entry):
    """One ledger append, exactly the bash writer's shape and failure markers. Returns the new entry."""
    ledger_dir = os.path.join(root, ".harness", "ledger")
    chain_file = os.path.join(ledger_dir, "chain.jsonl")
    fail_file = os.path.join(ledger_dir, "append-failures.jsonl")
    tool = (entry.get("action") or {}).get("tool", "")
    sid = (entry.get("actor") or {}).get("session_id", "")
    lk, stage = None, "lock"
    try:
        lk = _ledger_lock(ledger_dir)
        stage = "read-last-entry"
        prev_hash, next_idx = _last_link(chain_file)
    except Exception as exc:  # noqa: BLE001
        try:
            append_line(fail_file, json.dumps({"ts": now_utc(), "type": "append_failed", "stage": stage, "tool": tool,
                                               "session_id": sid, "reason": "%s: %s" % (type(exc).__name__, exc)},
                                              separators=(",", ":")))
        except Exception:  # noqa: BLE001
            pass
        if lk is not None:
            _ledger_unlock(lk)
        raise
    ts = now_utc()
    new_entry = {
        "index": next_idx, "prev_hash": prev_hash, "entry_hash": "", "timestamp": ts,
        "actor": entry.get("actor", {"agent": "unknown", "user": "unknown", "session_id": "", "role": ""}),
        "action": entry.get("action", {"type": "tool_call", "tool": "", "description": "", "input_hash": "", "output_hash": ""}),
        "decision": entry.get("decision", {"result": "allow", "reason": "", "risk_level": "none"}),
        "payload_ref": entry.get("payload_ref", ""),
        "signature": entry.get("signature", ""),
    }
    new_entry["entry_hash"] = entry_hash(new_entry)
    try:
        with open(chain_file, "a", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(new_entry, separators=(",", ":")) + "\n")
    except Exception as exc:  # noqa: BLE001
        marker = {"ts": ts, "type": "append_failed", "stage": "write-chain", "tool": tool, "session_id": sid,
                  "reason": "%s: %s" % (type(exc).__name__, exc)}
        try:
            append_line(fail_file, json.dumps(marker, separators=(",", ":")))
        except Exception:  # noqa: BLE001
            try:
                append_line(os.path.join(root, ".harness", "telemetry", "hook-errors.log"),
                            "%s LEDGER-APPEND-LOST tool=%s :: %s" % (ts, tool, marker["reason"]))
            except Exception:  # noqa: BLE001
                pass
        _ledger_unlock(lk)
        raise
    _ledger_unlock(lk)
    return new_entry


class LedgerWriter(threading.Thread):
    """The one writer: hooks enqueue, this thread appends. A full queue is recorded, never silent."""

    def __init__(self, maxsize):
        super().__init__(name="harnessd-ledger", daemon=True)
        self.q = Queue(maxsize=max(100, int(maxsize or 10000)))
        self.stop_flag = threading.Event()
        self.written = 0
        self.failed = 0

    def enqueue(self, root, entry):
        try:
            self.q.put_nowait((root, entry))
            return True
        except Full:
            self.failed += 1
            hook_error(root, "ledger queue full -- entry for tool=%s dropped (recorded in append-failures.jsonl)"
                       % (entry.get("action") or {}).get("tool", ""))
            try:
                append_line(os.path.join(root, ".harness", "ledger", "append-failures.jsonl"),
                            json.dumps({"ts": now_utc(), "type": "append_failed", "stage": "queue",
                                        "tool": (entry.get("action") or {}).get("tool", ""),
                                        "session_id": (entry.get("actor") or {}).get("session_id", ""),
                                        "reason": "harnessd ledger queue full"}, separators=(",", ":")))
            except Exception:  # noqa: BLE001
                pass
            return False

    def run(self):
        while not (self.stop_flag.is_set() and self.q.empty()):
            try:
                root, entry = self.q.get(timeout=0.5)
            except Empty:
                continue
            t0 = time.perf_counter()
            try:
                append_entry(root, entry)
                self.written += 1
                ms = (time.perf_counter() - t0) * 1000
                if ms > 2000:
                    hook_error(root, "ledger append took %dms (expected <100ms) -- chain may hold an oversized entry" % ms)
            except Exception as e:  # noqa: BLE001
                self.failed += 1
                hook_error(root, "ledger append failed for tool=%s :: %s: %s"
                           % ((entry.get("action") or {}).get("tool", ""), type(e).__name__, e))
            finally:
                self.q.task_done()

    def flush(self, timeout=30.0):
        deadline = time.time() + timeout
        while not self.q.empty() and time.time() < deadline:
            time.sleep(0.05)
        return self.q.empty()


# ----------------------------------------------------------------- the guard

def _command_of(tool_input):
    if isinstance(tool_input, dict):
        for k in ("command", "script"):
            v = tool_input.get(k)
            if v:
                return str(v)
    return ""


def _deny_text(reason, tool, command=""):
    snip = ""
    if command:
        snip = " | command: " + command[:200]
    return "[%s] DENIED tool=%s :: %s%s" % (GUARD, tool, reason, snip)


def _git_head(root):
    try:
        r = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True, timeout=5)
        return (r.stdout or "").strip().splitlines()[0].strip() if r.returncode == 0 and r.stdout.strip() else ""
    except (OSError, subprocess.SubprocessError, IndexError):
        return ""


def _pdp_consult(root, pol, tool, short, command, payload, warnings):
    """-> (decision, reason, approval_id) or None when the PDP was not asked / unreachable."""
    sync_root, cfg = pol.sync()
    if not (cfg.get("pdp_enforce") is True and cfg.get("portal_url") and cfg.get("project_id")):
        return None
    high = bool(_HR1.search(command) or _HR2.search(command) or _HR3.search(command) or short in _HR_TOOLS)
    if not high:
        return None
    legacy = os.environ.get("HARNESS_PORTAL_INGEST_KEY", "")
    if not legacy:
        kf = os.path.join(sync_root, ".harness", "portal-sync.key")
        try:
            with open(kf, encoding="utf-8-sig") as f:
                legacy = f.read().strip()
        except OSError:
            legacy = ""
    headers, source = facts.auth_headers(root, legacy, portal_url=str(cfg["portal_url"]))
    if source == "blocked":
        w = facts.blocked_warning(GUARD, facts.check_portal_url(root, str(cfg["portal_url"]))[1])
        if w:
            warnings.append(w)
        return None
    if not headers:
        return None
    if source == "legacy-key":
        w = facts.legacy_warning(GUARD)
        if w:
            warnings.append(w)
    actor = os.environ.get("HARNESS_USER") or payload.get("session_id") or os.environ.get("HARNESS_SESSION_ID", "")
    body = {"tool": tool, "command": command, "actor": actor,
            "actor_host": os.environ.get("COMPUTERNAME") or socket.gethostname(),
            "commit_head": _git_head(root)}
    url = str(cfg["portal_url"]).rstrip("/") + "/api/pdp/" + str(cfg["project_id"]) + "/decide"
    req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), method="POST",
                                 headers={"Content-Type": "application/json; charset=utf-8",
                                          "User-Agent": "harness-runtime-guard/1.0", **headers})
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            d = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            w = facts.rejected_warning(GUARD)
            if w:
                warnings.append(w)
        return None
    except Exception:  # noqa: BLE001 -- fail-open on network trouble (C10)
        return None
    if not isinstance(d, dict):
        return None
    return str(d.get("decision") or ""), str(d.get("reason") or ""), str(d.get("approval_id") or "")


def evaluate_pre(root, payload):
    """The PreToolUse verdict for one hook payload. Pure except for the PDP/F2 network
    calls the shipped guards also make. Returns a dict:
      {"decision": "allow"|"deny", "reason", "label", "severity", "event", "command", "warnings": [...]}
    """
    pol = policy_for(root)
    tool = str(payload.get("tool_name") or payload.get("tool") or "")
    tool_input = payload.get("tool_input") if payload.get("tool_input") is not None else payload.get("input")
    if not isinstance(tool_input, dict):
        tool_input = {}
    command = _command_of(tool_input)
    short = short_tool(tool)
    warnings = []

    def deny(reason, label, severity="high", event="guard_block", cmd=command):
        return {"decision": "deny", "reason": reason, "label": label, "severity": severity,
                "event": event, "command": cmd, "tool": tool, "warnings": warnings}

    # 1) H4 command deny patterns (risk-policy.yaml)
    if command:
        for pat, rx in pol.deny_patterns():
            try:
                hit = rx.search(command)
            except Exception:  # noqa: BLE001
                continue
            if hit:
                return deny("Command matched deny pattern: %s" % pat, "deny pattern: %s" % pat)

    # 1b) C17 write scope: writes only inside the granted project folder (+ its Claude
    # memory dir). The granted root comes from the transcript path, not from `cwd`
    # (a session can cd anywhere) and never from the daemon's own home. Fail-open on
    # an error in the check itself (C10); a verdict of deny is final.
    try:
        cwd_root = find_root(payload.get("cwd") or "")
        ws = wscope.decide_pre(payload, cwd_root)
        if ws.get("decision") == "deny":
            return deny(ws.get("reason", ""), ws.get("label", "C17:write-scope"),
                        cmd=command or "; ".join(ws.get("targets") or []))
        wscope.before_shell(payload, cwd_root)
    except Exception as e:  # noqa: BLE001
        hook_error(root, "C17 write-scope check failed (fail-open): %s" % e)

    # 2) C16 worktree budget (harness_worktree decides, C7 shared core)
    try:
        v = wt.decide_guard(root, payload)
        if v.get("decision") == "deny":
            return deny(v.get("reason", ""), "C16:worktree-budget")
    except Exception:  # noqa: BLE001
        pass

    # 3) C3/C6 tool-registry deny-by-default
    tools = pol.registry()
    for key in registry_candidates(tool, tools):
        ent = tools.get(key)
        if isinstance(ent, dict):
            if ent.get("default_action") == "deny":
                risk = str(ent.get("risk_level") or "")
                ov = {}
                try:
                    ov = pol.tool_overrides().get(key) or {}
                except Exception:  # noqa: BLE001 -- an unreadable override never relaxes anything
                    ov = {}
                if ov:
                    # Owner's per-project override: ASK the person every time, never allow.
                    reason = ("Tool '%s' (registry key '%s', risk '%s') is deny-by-default; this project's owner "
                              "turned it into ASK (.harness/project/tool-overrides.json: %s -- approved by %s on %s%s). "
                              "Approve only if this exact call is what you want."
                              % (tool, key, risk, ov.get("reason"), ov.get("approved_by"), ov.get("approved_on"),
                                 (", expires %s" % ov["expires_on"]) if ov.get("expires_on") else ""))
                    return {"decision": "ask", "reason": reason, "label": "override-ask (%s)" % risk,
                            "severity": risk or "high", "event": "override_ask", "command": command,
                            "tool": tool, "warnings": warnings}
                return deny("Tool '%s' (registry key '%s') has risk level '%s' — deny-by-default" % (tool, key, risk),
                            "deny-by-default (%s)" % risk, severity=risk or "high")
            break

    # 4) server-side PDP (opt-in via portal-sync.json pdp_enforce)
    if command:
        try:
            r = _pdp_consult(root, pol, tool, short, command, payload, warnings)
        except Exception:  # noqa: BLE001
            r = None
        if r and r[0] in ("deny", "ask"):
            reason = "PDP %s: %s" % (r[0], r[1])
            d = deny(reason, "pdp:%s" % r[0], event="pdp_block")
            d["approval_id"] = r[2]
            return d

    # 5) F2 sensitivity (only writes; fail-open)
    try:
        s = pol.sensitive()
        if s and s["enforce"] and tool in _WRITE_TOOLS:
            target = ""
            for k in ("file_path", "path", "notebook_path"):
                if tool_input.get(k):
                    target = str(tool_input[k])
                    break
            if target:
                rel = target
                if target.lower().startswith(root.lower()):
                    rel = target[len(root):].lstrip("\\/")
                delta, rid, why_rule = sens.match(rel, s["rules"])
                score = sens.BASE_FILE_WRITE + delta
                tier = sens.tier_of(score, s["tiers"])
                if rid and tier in ("high", "critical"):
                    why = ("F2 sensitivity: '%s' khop rule '%s' -> diem %s (tier %s). %s Can nguoi duyet truoc khi ghi."
                           % (rel, rid, score, tier, why_rule))
                    portal = None
                    if sens.approvable(rel, s["rules"], s["cfg"]):
                        portal = sens.ask_portal(root, rel, rid, tool, tool_input)
                    if portal and portal.get("decision") == "allow":
                        return {"decision": "allow", "reason": "F2 approved by Portal", "warnings": warnings, "tool": tool}
                    if portal and portal.get("decision") != "skip":
                        if portal.get("approval_id"):
                            why += (" Portal: %s (approval_id=%s) - nguoi duyet vao Portal > Approvals duyet dung file nay, roi chay lai."
                                    % (portal["decision"], portal["approval_id"]))
                        else:
                            why += " Khong hoi duoc Portal (%s) - giu nguyen chan." % portal.get("reason", "")
                    return deny(why, "sensitivity:%s" % rid, cmd=rel)
    except Exception:  # noqa: BLE001
        pass

    return {"decision": "allow", "reason": "", "warnings": warnings, "tool": tool}


def record_deny(root, payload, verdict, writer=None):
    """Same evidence the shipped guards leave on a deny: a security event and a ledger entry."""
    tool = verdict.get("tool", "")
    cmd = verdict.get("command", "")
    excerpt = ('blocked command: "%s" | matched deny-pattern: %s' % (cmd[:240], verdict.get("label", "")))
    if verdict.get("event") == "pdp_block":
        excerpt = "PDP block: %s | approval_id=%s" % (verdict.get("reason", ""), verdict.get("approval_id", ""))
    security_event(root, payload, verdict.get("event", "guard_block"), verdict.get("severity", "high"), tool, excerpt)
    entry = {"actor": _actor(payload),
             "action": {"type": "tool_call", "tool": tool, "description": "blocked by runtime guard",
                        "input_hash": sha256(cmd), "output_hash": ""},
             "decision": {"result": "deny", "reason": "deny pattern: %s" % verdict.get("label", ""), "risk_level": "high"}}
    if writer is not None:
        writer.enqueue(root, entry)
    else:
        try:
            append_entry(root, entry)
        except Exception as e:  # noqa: BLE001
            hook_error(root, "ledger deny entry failed: %s" % e)


def pre_response(verdict):
    """The JSON object Claude Code reads (empty dict = plain allow)."""
    out = {}
    if verdict.get("warnings"):
        out["systemMessage"] = "\n".join(verdict["warnings"])
    if verdict["decision"] == "deny":
        out["hookSpecificOutput"] = {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                     "permissionDecisionReason": _deny_text(verdict["reason"], verdict.get("tool", ""),
                                                                            verdict.get("command", ""))}
    elif verdict["decision"] == "ask":
        # A per-project owner override: Claude Code asks the person; the guard never allows.
        out["hookSpecificOutput"] = {"hookEventName": "PreToolUse", "permissionDecision": "ask",
                                     "permissionDecisionReason": verdict.get("reason", "")}
    return out


def record_ask(root, payload, verdict):
    """Evidence that a deny was relaxed to ask by an owner override (C9/C12)."""
    security_event(root, payload, "override_ask", "info", verdict.get("tool", ""),
                   ("deny-by-default relaxed to ASK by .harness/project/tool-overrides.json | %s"
                    % verdict.get("reason", ""))[:400])


def handle_post(root, payload, writer=None):
    """PostToolUse: telemetry line, ledger entry, qa-gate. Returns the JSON object for Claude Code."""
    pol = policy_for(root)
    tool = str(payload.get("tool_name") or payload.get("tool") or "")
    tool_input = payload.get("tool_input") if payload.get("tool_input") is not None else payload.get("input")
    tool_result = payload.get("tool_response") if payload.get("tool_response") is not None else payload.get("result")
    agent = str(payload.get("agent") or "claude-code")
    try:
        append_line(os.path.join(root, ".harness", "telemetry", "tool-calls.log"),
                    json.dumps({"timestamp": now_iso(), "agent": agent, "tool": tool,
                                "success": payload.get("success"),
                                "session_id": payload.get("session_id") or os.environ.get("HARNESS_SESSION_ID", "")}))
    except Exception as e:  # noqa: BLE001
        hook_error(root, "tool-calls.log not written: %s" % e)
    tin = json.dumps(tool_input, separators=(",", ":"), ensure_ascii=False) if tool_input else "{}"
    tout = json.dumps(tool_result, separators=(",", ":"), ensure_ascii=False) if tool_result else "{}"
    entry = {"actor": _actor(payload, agent),
             "action": {"type": "tool_call", "tool": tool, "description": "completed tool call",
                        "input_hash": sha256(tin), "output_hash": sha256(tout)},
             "decision": {"result": "allow", "reason": "completed", "risk_level": "none"}}
    if writer is not None:
        writer.enqueue(root, entry)
    else:
        try:
            append_entry(root, entry)
        except Exception as e:  # noqa: BLE001
            hook_error(root, "ledger append failed for tool=%s :: %s" % (tool, e))
    # C17 detection: an entry that appeared in the drive root / beside the project while
    # this shell command ran. Cannot undo it; makes it visible to the session and logged.
    c17 = None
    try:
        new = wscope.after_shell(payload)
        if new:
            groot, _src = wscope.granted_root(payload, find_root(payload.get("cwd") or ""))
            msg = wscope.detection_message(new, groot or root)
            security_event(root, payload, "write_scope", "high", tool, msg[:400])
            c17 = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg},
                   "systemMessage": msg}
    except Exception as e:  # noqa: BLE001
        hook_error(root, "C17 detection failed: %s" % e)
    # qa-gate (casan-policies governance.qa_gate) -- fail-closed once enabled
    try:
        enabled, blocking = pol.qa_gate()
    except Exception:  # noqa: BLE001
        enabled, blocking = False, []
    if enabled and tool and tool in blocking:
        try:
            verdict, vpath = pol.qa_verdict()
        except Exception as e:  # noqa: BLE001
            return {"decision": "block", "reason": "qa-gate block: gate check failed to run (%s) -- fail-closed." % e}
        if verdict != "APPROVED":
            if not verdict:
                reason = ("qa-gate block: verdict missing -- fail-closed. The gate is enabled in casan-policies.yaml "
                          "but pipeline-context.yaml carries no qa_gate_verdict. Run the qa-gate stage, or set "
                          "governance.qa_gate.enabled: false.")
            else:
                reason = "qa-gate block: verdict=%s (needs APPROVED) for tool '%s'. Resolve at %s." % (verdict, tool, vpath)
            reason += " This is a LOCAL hook -- defense-in-depth, not a boundary. Release actions need server-side enforcement at the gateway (C10)."
            return {"decision": "block", "reason": reason}
    return c17 or {}


# ----------------------------------------------------------------- the server

class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.samples = {"pre": [], "post": []}
        self.counts = {"pre": 0, "post": 0, "deny": 0, "block": 0, "unrouted": 0, "unauthorized": 0}
        self.last_request = time.time()

    def add(self, kind, ms, **flags):
        with self.lock:
            self.last_request = time.time()
            if kind in self.samples:
                s = self.samples[kind]
                s.append(ms)
                if len(s) > 2000:
                    del s[:1000]
                self.counts[kind] += 1
            for k, v in flags.items():
                if v:
                    self.counts[k] = self.counts.get(k, 0) + 1

    @staticmethod
    def _pct(s, p):
        if not s:
            return None
        s = sorted(s)
        return round(s[min(len(s) - 1, int(len(s) * p))], 2)

    def snapshot(self):
        with self.lock:
            return {"counts": dict(self.counts),
                    "pre_p50_ms": self._pct(self.samples["pre"], 0.50), "pre_p95_ms": self._pct(self.samples["pre"], 0.95),
                    "post_p50_ms": self._pct(self.samples["post"], 0.50), "post_p95_ms": self._pct(self.samples["post"], 0.95),
                    "idle_s": round(time.time() - self.last_request, 1)}


class _Server(ThreadingHTTPServer):
    """ThreadingHTTPServer that counts in-flight requests. Handler threads stay daemon
    threads (exit must never be blocked by a client holding a connection), but the count
    lets a stopping daemon wait, bounded, for the replies it still owes -- ThreadingMixIn's
    own join skips daemon threads, so block_on_close would wait for nothing."""
    daemon_threads = True

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self.inflight = 0
        self._inflight_lock = threading.Lock()

    def process_request(self, request, client_address):
        # Counted HERE, in the accept loop, before the thread starts: after shutdown() the
        # loop has exited, so every accepted request is already in the count.
        with self._inflight_lock:
            self.inflight += 1
        try:
            super().process_request(request, client_address)
        except Exception:
            with self._inflight_lock:
                self.inflight -= 1
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            with self._inflight_lock:
                self.inflight -= 1

    def wait_inflight(self, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self._inflight_lock:
                if self.inflight <= 0:
                    return True
            time.sleep(0.02)
        with self._inflight_lock:
            return self.inflight <= 0


class Daemon:
    def __init__(self, home, port, cfg, inherited=None, takeover_from=None):
        self.home = home
        self.port = int(port)
        self.cfg = cfg
        self.started = time.time()
        self.stats = Stats()
        self.writer = LedgerWriter(cfg.get("ledger_queue_max"))
        self.token = os.environ.get("HARNESSD_TOKEN", "")
        # H2 (23-11): /shutdown needs THIS daemon's own secret, written to a per-user state file
        # only local clients (`stop`, `ensure`) read. The hook token above stays as it was:
        # Claude Code sends $HARNESSD_TOKEN, empty on every machine, and refusing that would
        # fail every hook open.
        self.admin_token = uuid.uuid4().hex + uuid.uuid4().hex
        self.log_path = os.path.join(state_dir(), "harnessd.log")
        self.stop_event = threading.Event()
        self.server = None
        self.inherited = inherited          # a listening socket handed over by the previous daemon
        self.takeover_from = takeover_from  # its pid, for /health and the log
        self.self_mtime = self._lib_mtimes()

    @staticmethod
    def _lib_mtimes():
        """mtimes of this file AND every harness_*.py beside it: a policy core (worktree,
        sensitivity, checkout facts) edited on disk must not keep serving from memory."""
        out = {}
        for n in os.listdir(HERE):
            if n == os.path.basename(__file__) or (n.startswith("harness_") and n.endswith(".py")):
                try:
                    out[n] = os.path.getmtime(os.path.join(HERE, n))
                except OSError:
                    pass
        return out

    def log(self, **kv):
        try:
            kv.setdefault("ts", now_iso())
            if os.path.exists(self.log_path) and os.path.getsize(self.log_path) > 5 * 1024 * 1024:
                try:
                    os.replace(self.log_path, self.log_path + ".1")
                except OSError:
                    pass
            append_line(self.log_path, json.dumps(kv, ensure_ascii=False))
        except Exception:  # noqa: BLE001
            pass

    def health(self):
        s = self.stats.snapshot()
        s.update({"ok": True, "version": VERSION, "pid": os.getpid(), "port": self.port, "home": self.home,
                  "uptime_s": round(time.time() - self.started, 1), "ledger_written": self.writer.written,
                  "ledger_failed": self.writer.failed, "ledger_queued": self.writer.q.qsize(),
                  "token": bool(self.token), "roots": sorted(_policies.keys()),
                  "takeover_from": self.takeover_from})
        return s

    def write_admin_token(self):
        try:
            p = admin_token_path(self.port)
            fd = os.open(p + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(self.admin_token)
            os.replace(p + ".tmp", p)
        except OSError as e:
            self.log(event="admin_token_write_failed", error=str(e))

    def write_state(self):
        try:
            with open(state_path(), "w", encoding="utf-8") as f:
                json.dump({"pid": os.getpid(), "port": self.port, "version": VERSION, "home": self.home,
                           "started_at": now_iso(), "log": self.log_path}, f, indent=1)
        except OSError:
            pass

    def resolve_root(self, payload):
        return policy_root(payload, self.home)

    def idle_loop(self):
        limit = float(self.cfg.get("idle_exit_minutes") or 0) * 60
        while not self.stop_event.wait(30):
            try:
                cur = self._lib_mtimes()
                if cur != self.self_mtime:
                    # Let an editor finish writing (two identical reads 2 s apart) before
                    # starting the new code; a half-written file would fail to import.
                    time.sleep(2.0)
                    cur2 = self._lib_mtimes()
                    if cur2 != cur:
                        continue
                    self.self_mtime = cur2          # one attempt per change set
                    if self.handover():
                        return
            except OSError:
                pass
            if limit and time.time() - self.stats.last_request > limit:
                self.log(event="exit", why="idle for %d minutes" % int(limit / 60))
                self.shutdown()
                return

    def handover(self):
        """A lib file changed: start the NEW daemon on THIS listening socket, wait until it
        serves (it writes state.json with its pid), then stop accepting here. Both answer
        the same socket meanwhile, so no request is refused (B-99). Returns True when this
        process should now exit. If the new code cannot start, keep serving the OLD code
        and leave one line in hook-errors.log -- a silent fallback would be a lie (C12)."""
        self.log(event="handover", why="a lib file changed on disk")
        try:
            proc = _spawn(self.home, self.port, inherit=self.server.socket, takeover_from=os.getpid())
        except Exception as e:  # noqa: BLE001
            hook_error(self.home, "harnessd: could not start the new daemon after a lib change (%s: %s) -- "
                                  "still serving the OLD code until the lib is fixed" % (type(e).__name__, e))
            self.log(event="handover_failed", error="%s: %s" % (type(e).__name__, e))
            return False
        deadline = time.time() + HANDOVER_WAIT_S
        while time.time() < deadline:
            st = read_state()
            if st.get("pid") == proc.pid:
                self.log(event="handover_done", to_pid=proc.pid, version=st.get("version"))
                self.shutdown()
                return True
            if proc.poll() is not None:
                hook_error(self.home, "harnessd: the new daemon exited at start with code %s after a lib change -- "
                                      "still serving the OLD code until the lib is fixed (harnessd.log)" % proc.returncode)
                self.log(event="handover_failed", code=proc.returncode)
                return False
            time.sleep(0.1)
        hook_error(self.home, "harnessd: the new daemon did not become ready within %ds after a lib change -- "
                              "still serving the OLD code; if it comes up later both answer the port" % int(HANDOVER_WAIT_S))
        self.log(event="handover_failed", why="timeout", pid=proc.pid)
        return False

    def shutdown(self):
        if self.stop_event.is_set():
            return
        self.stop_event.set()
        threading.Thread(target=self._stop_server, daemon=True).start()

    def _stop_server(self):
        try:
            if self.server:
                self.server.shutdown()
        except Exception:  # noqa: BLE001
            pass

    def serve(self):
        daemon = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):  # quiet; harnessd.log is the record
                pass

            def _send(self, code, obj=None):
                body = b"" if obj is None or obj == {} else json.dumps(obj, ensure_ascii=False).encode("utf-8")
                self.send_response(code)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                if body:
                    self.wfile.write(body)

            def _authorized(self):
                if not daemon.token:
                    return True
                return (self.headers.get("X-Harnessd-Token") or "") == daemon.token

            def _from_a_browser(self):
                """H2 (23-11): a web page can POST here (no-cors) and, after DNS rebinding, with any
                Host. Hook clients send neither an Origin nor a foreign Host."""
                if self.headers.get("Origin") is not None:
                    return True
                host = (self.headers.get("Host") or "").strip().lower()
                return bool(host) and host not in {"127.0.0.1:%d" % daemon.port, "localhost:%d" % daemon.port,
                                                   "[::1]:%d" % daemon.port, "127.0.0.1", "localhost"}

            def do_GET(self):
                if self._from_a_browser():
                    daemon.stats.add("other", 0, unauthorized=True)
                    return self._send(403, {"error": "browser requests are refused"})
                if self.path.rstrip("/") == "/health":
                    return self._send(200, daemon.health())
                daemon.stats.add("other", 0, unrouted=True)
                return self._send(404, {"error": "no such route"})

            def do_POST(self):
                t0 = time.perf_counter()
                n = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(n) if n else b""   # read first: answering before draining resets the socket
                path = self.path.rstrip("/")
                if self._from_a_browser():
                    daemon.stats.add("other", 0, unauthorized=True)
                    daemon.log(event="refused", why="browser request", path=self.path,
                               origin=str(self.headers.get("Origin") or "")[:80])
                    return self._send(403, {"error": "browser requests are refused"})
                if path == "/shutdown":
                    got = self.headers.get("X-Harnessd-Admin") or ""
                    if not hmac.compare_digest(got.encode("utf-8"), daemon.admin_token.encode("utf-8")):
                        daemon.stats.add("other", 0, unauthorized=True)
                        daemon.log(event="refused", why="/shutdown without the daemon secret")
                        return self._send(401, {"error": "shutdown needs the daemon secret (harnessd.py stop)"})
                elif not self._authorized():
                    daemon.stats.add("other", 0, unauthorized=True)
                    return self._send(401, {"error": "bad token"})
                try:
                    payload = json.loads(raw.decode("utf-8", "replace")) if raw else {}
                    if not isinstance(payload, dict):
                        payload = {}
                except ValueError:
                    payload = {}
                if path == "/shutdown":
                    self._send(200, {"ok": True, "stopping": True})
                    daemon.log(event="shutdown", by="request")
                    daemon.shutdown()
                    return
                root = daemon.resolve_root(payload)
                tool = str(payload.get("tool_name") or payload.get("tool") or "")
                if path == "/hook/pre-tool-use":
                    out = {}
                    try:
                        v = evaluate_pre(root, payload)
                        if v["decision"] == "deny":
                            record_deny(root, payload, v, daemon.writer)
                        elif v["decision"] == "ask":
                            record_ask(root, payload, v)
                        out = pre_response(v)
                    except Exception as e:  # noqa: BLE001 -- fail-open, but recorded
                        hook_error(root, "pre-tool-use crashed for tool=%s :: %s: %s" % (tool, type(e).__name__, e))
                        v = {"decision": "allow"}
                    ms = (time.perf_counter() - t0) * 1000
                    daemon.stats.add("pre", ms, deny=(v["decision"] == "deny"))
                    daemon.log(event="pre", tool=tool, decision=v["decision"], ms=round(ms, 2),
                               root=root, session=str(payload.get("session_id") or "")[:12])
                    return self._send(200, out)
                if path == "/hook/post-tool-use":
                    out = {}
                    try:
                        out = handle_post(root, payload, daemon.writer)
                    except Exception as e:  # noqa: BLE001
                        hook_error(root, "post-tool-use crashed for tool=%s :: %s: %s" % (tool, type(e).__name__, e))
                    ms = (time.perf_counter() - t0) * 1000
                    daemon.stats.add("post", ms, block=bool(out.get("decision") == "block"))
                    daemon.log(event="post", tool=tool, decision=("block" if out.get("decision") == "block" else "ok"),
                               ms=round(ms, 2), root=root)
                    return self._send(200, out)
                daemon.stats.add("other", 0, unrouted=True)
                daemon.log(event="unrouted", path=self.path)
                return self._send(404, {"error": "no such route"})

        if self.inherited is not None:
            # Serve on the socket the previous daemon handed over: already bound and
            # listening there, so no bind here and no moment with the port empty.
            self.server = _Server(("127.0.0.1", self.port), Handler, bind_and_activate=False)
            try:
                self.server.socket.close()
            except OSError:
                pass
            self.server.socket = self.inherited
            self.server.server_address = self.inherited.getsockname()[:2]
            self.server.server_name, self.server.server_port = "127.0.0.1", self.port
            self.server.server_activate()
        else:
            self.server = _Server(("127.0.0.1", self.port), Handler)
        self.writer.start()
        threading.Thread(target=self.idle_loop, daemon=True).start()
        self.write_admin_token()   # before state.json: a client that sees this pid can stop it
        self.write_state()   # the previous daemon reads this pid as "the new one serves"
        self.log(event="start", pid=os.getpid(), port=self.port, home=self.home, version=VERSION,
                 takeover_from=self.takeover_from)
        try:
            self.server.serve_forever(poll_interval=0.5)
        finally:
            # A request this process accepted must be answered by this process: handler
            # threads are daemon threads, so exiting now would cut one mid-reply and the
            # client would see "RemoteDisconnected" -- seen once on the server CI during a
            # handover (13-11). Wait for the in-flight ones (bounded: a keep-alive client
            # could otherwise hold this process open forever).
            if not self.server.wait_inflight(5.0):
                self.log(event="exit_with_inflight", inflight=self.server.inflight)
            self.writer.stop_flag.set()
            self.writer.flush(30)
            self.log(event="stopped", ledger_written=self.writer.written, ledger_failed=self.writer.failed)
            try:
                st = read_state()
                if st.get("pid") == os.getpid():
                    os.remove(state_path())
            except OSError:
                pass
            try:
                if read_admin_token(self.port) == self.admin_token:   # not a successor's secret
                    os.remove(admin_token_path(self.port))
            except OSError:
                pass


# ----------------------------------------------------------------- client side

def health(port, timeout=1.0):
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/health" % int(port), timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:  # noqa: BLE001
        return None


def admin_token_path(port):
    return os.path.join(state_dir(), "admin-%d.token" % int(port))


def read_admin_token(port):
    try:
        with open(admin_token_path(port), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def post(port, path, obj, timeout=10.0, token=""):
    headers = {"Content-Type": "application/json", "X-Harnessd-Token": token or os.environ.get("HARNESSD_TOKEN", "")}
    if path.rstrip("/") == "/shutdown":
        # H2: the running daemon's own secret. A daemon older than 0.3.3 ignores the header.
        headers["X-Harnessd-Admin"] = read_admin_token(port)
    req = urllib.request.Request("http://127.0.0.1:%d%s" % (int(port), path), method="POST",
                                 data=json.dumps(obj).encode("utf-8"), headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read().decode("utf-8")
        return r.status, (json.loads(raw) if raw.strip() else {})


def _spawn(home, port, inherit=None, takeover_from=None):
    """Start a detached `serve`. With `inherit` (a listening socket) the child serves on
    THAT socket: Windows duplicates it into the child (socket.share -> stdin), POSIX passes
    the fd. `takeover_from` is the old pid, recorded by the child for /health."""
    exe = sys.executable
    if os.name == "nt":
        pw = os.path.join(os.path.dirname(exe), "pythonw.exe")
        if os.path.isfile(pw):
            exe = pw
    args = [exe, os.path.abspath(__file__), "serve", "--home", home, "--port", str(port)]
    if takeover_from:
        args += ["--takeover", str(takeover_from)]
    kw = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL, "close_fds": True}
    if os.name == "nt":
        kw["creationflags"] = 0x00000008 | 0x00000200 | 0x08000000   # DETACHED | NEW_PROCESS_GROUP | NO_WINDOW
    else:
        kw["start_new_session"] = True
    if inherit is None:
        return subprocess.Popen(args, **kw)
    if os.name == "nt":
        args += ["--inherit", "share"]
        kw["stdin"] = subprocess.PIPE
        proc = subprocess.Popen(args, **kw)
        try:
            proc.stdin.write(inherit.share(proc.pid))
            proc.stdin.close()
        except Exception:
            proc.kill()
            raise
        return proc
    fd = inherit.fileno()
    args += ["--inherit", str(fd)]
    kw["pass_fds"] = (fd,)
    return subprocess.Popen(args, **kw)


def ensure(home, port=None, wait_s=8.0, quiet=True):
    """Start the daemon if it is not healthy; restart it when the running one is older
    than this file. Prints only when something changed. Never raises."""
    cfg = daemon_config(home)
    if cfg.get("enabled") is False:
        return 0
    port = int(port or cfg["port"])
    h = health(port)
    if h and h.get("ok"):
        running = _vtuple(h.get("version"))
        if running >= _vtuple(VERSION):
            # Same or NEWER code already serves this machine (every project's lib ships its
            # own harnessd.py; a project still on an older bundle must not pull the daemon
            # back down, or two projects' prompts would restart it at each other, each
            # restart being a gap -- measured 13-11 22:01 between 0.2.0 and 0.1.0).
            return 0
        try:
            post(port, "/shutdown", {}, timeout=3)
            for _ in range(20):
                if not health(port, 0.3):
                    break
                time.sleep(0.1)
        except Exception:  # noqa: BLE001
            pass
    elif _port_busy(port):
        hook_error(home, "harnessd: port %d is held by another process -- http hooks will not reach the daemon" % port)
        print("[harnessd] port %d busy, not ours" % port)
        return 0
    try:
        proc = _spawn(home, port)
    except Exception as e:  # noqa: BLE001
        hook_error(home, "harnessd could not start: %s: %s" % (type(e).__name__, e))
        print("[harnessd] could not start: %s" % e)
        return 0
    deadline = time.time() + wait_s
    while time.time() < deadline:
        h = health(port, 0.3)
        if h and h.get("ok"):
            print("[harnessd] started pid=%s port=%d version=%s" % (h.get("pid"), port, h.get("version")))
            return 0
        if proc.poll() is not None:
            # The process is gone: that is an error worth a line (port taken, import failure...).
            hook_error(home, "harnessd exited at start with code %s (port %d) -- see harnessd.log / run `harnessd.py serve` by hand"
                       % (proc.returncode, port))
            print("[harnessd] exited at start (code %s)" % proc.returncode)
            return 0
        time.sleep(0.1)
    # Still starting (a cold python on a busy box can take longer than this wait): NOT an
    # error -- a false alarm here would cost the channel (C14). The next prompt's ensure
    # finds it healthy and stays silent.
    print("[harnessd] spawned pid=%s, still starting" % proc.pid)
    return 0


def _vtuple(v):
    """'0.2.0' -> (0, 2, 0); anything unparseable sorts lowest (gets replaced)."""
    out = []
    for part in str(v or "").split("."):
        try:
            out.append(int(part))
        except ValueError:
            break
    return tuple(out) if out else (-1,)


def _port_busy(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", int(port))) == 0
    finally:
        s.close()


def bench(port, n=200):
    payload = {"hook_event_name": "PreToolUse", "tool_name": "Read", "tool_input": {"file_path": "README.md"},
               "cwd": os.getcwd(), "session_id": "bench"}
    times = []
    for _ in range(int(n)):
        t0 = time.perf_counter()
        post(port, "/hook/pre-tool-use", payload, timeout=10)
        times.append((time.perf_counter() - t0) * 1000)
    times.sort()
    return {"n": len(times), "p50_ms": round(times[len(times) // 2], 2),
            "p95_ms": round(times[min(len(times) - 1, int(len(times) * 0.95))], 2), "max_ms": round(times[-1], 2)}


# ----------------------------------------------------------------- CLI

def main(argv):
    args = list(argv[1:])
    cmd = args[0] if args else "status"
    home = None
    port = None
    inherit = None
    takeover = None
    i = 1
    rest = []
    while i < len(args):
        if args[i] == "--home" and i + 1 < len(args):
            home = args[i + 1]
            i += 2
        elif args[i] == "--port" and i + 1 < len(args):
            port = int(args[i + 1])
            i += 2
        elif args[i] == "--inherit" and i + 1 < len(args):
            inherit = args[i + 1]
            i += 2
        elif args[i] == "--takeover" and i + 1 < len(args):
            takeover = int(args[i + 1])
            i += 2
        else:
            rest.append(args[i])
            i += 1
    home = find_root(home or os.environ.get("HARNESS_ROOT") or os.getcwd()) or os.path.abspath(home or os.getcwd())
    cfg = daemon_config(home)
    port = int(port or cfg["port"])

    if cmd == "serve":
        sock = None
        if inherit:
            try:
                if inherit == "share":          # Windows: the previous daemon wrote socket.share() bytes to our stdin
                    sock = socket.fromshare(sys.stdin.buffer.read())
                else:                           # POSIX: an inherited fd
                    sock = socket.socket(fileno=int(inherit))
            except Exception as e:  # noqa: BLE001
                hook_error(home, "harnessd: could not take over the listening socket from pid %s (%s: %s)"
                                 % (takeover, type(e).__name__, e))
                return 1
        d = Daemon(home, port, cfg, inherited=sock, takeover_from=takeover)
        try:
            d.serve()
        except OSError as e:
            hook_error(home, "harnessd serve failed on port %d: %s" % (port, e))
            return 1
        return 0
    if cmd == "ensure":
        return ensure(home, port)
    if cmd == "start":
        ensure(home, port)
        h = health(port)
        print(json.dumps(h or {"ok": False, "port": port}, indent=1))
        return 0 if h else 1
    if cmd == "stop":
        try:
            post(port, "/shutdown", {}, timeout=3)
            print("[harnessd] stop requested on port %d" % port)
            return 0
        except Exception as e:  # noqa: BLE001
            print("[harnessd] nothing answered on port %d (%s)" % (port, e))
            return 1
    if cmd == "status":
        h = health(port)
        st = read_state()
        out = {"port": port, "home": home, "healthy": bool(h), "state_file": st, "health": h,
               "log": os.path.join(state_dir(), "harnessd.log")}
        print(json.dumps(out, indent=1, ensure_ascii=False))
        return 0 if h else 1
    if cmd == "bench":
        n = int(rest[0]) if rest else 200
        if not health(port):
            print("[harnessd] not running on port %d" % port)
            return 1
        print(json.dumps(bench(port, n)))
        return 0
    if cmd == "guard":
        # Cold path / tests: one PreToolUse payload on stdin -> verdict JSON on stdout, exit 2 on deny.
        try:
            payload = json.loads(sys.stdin.buffer.read().decode("utf-8-sig", "replace") or "{}")   # B-97: BOM-proof
        except ValueError:
            return 0
        root = policy_root(payload, home)
        v = evaluate_pre(root, payload)
        if v["decision"] == "deny":
            record_deny(root, payload, v)
            sys.stderr.write(_deny_text(v["reason"], v.get("tool", ""), v.get("command", "")) + "\n")
        elif v["decision"] == "ask":
            record_ask(root, payload, v)
        sys.stdout.write(json.dumps(pre_response(v)) + "\n")
        return 2 if v["decision"] == "deny" else 0
    print("usage: harnessd.py serve|start|ensure|stop|status|bench [n]|guard [--home <root>] [--port N]")
    return 2


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:  # noqa: BLE001
        pass
    sys.exit(main(sys.argv))
