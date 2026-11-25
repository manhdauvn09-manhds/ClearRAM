#!/usr/bin/env python3
"""C17 "Write scope" -- a session writes only inside the project folder it was granted.

Incident 14/15-11-2026: a session granted E:\\Develop\\AnyAIControlHub created 17 repo copies
(~11 GB) in the root of E:\\ (E:\\t96 ... E:\\t110b) through a script it wrote and ran.
The bundle's settings allowed Edit/Write/Bash/PowerShell on every path and no guard looked
at the write target. Owner's ruling (15-11): writes only inside the granted project folder;
the one exception is that project's own Claude memory directory -- not %TEMP%, not the
session scratchpad.

Called by harnessd (PreToolUse / PostToolUse). Three layers:
  1. File tools (Write / Edit / MultiEdit / NotebookEdit): the target path must resolve
     inside an allowed root. Exact -- this is the strong layer.
  2. Shell (Bash / PowerShell): write targets recognised by pattern (redirects, mkdir,
     New-Item, Copy-Item/cp destination, Out-File, git clone/worktree add, tar -C, ...),
     with variables assigned in the same command or in a script file the command runs
     resolved. Pattern-based: a path computed at run time is invisible to it (C10).
  3. Detection after a shell command: an entry that APPEARED during the command in the
     drive root or beside the project is reported to the session and logged as a
     security event. It cannot undo the write; it makes it visible.

The granted root comes from the hook payload's transcript_path: Claude Code keeps each
session under ~/.claude/projects/<key>/, where <key> is the project path with every
non-alphanumeric character turned into '-'. The key is decoded back against the real
directory tree, so a session that `cd`s elsewhere still has the right root (C13); when
that fails, the root harnessd resolved from `cwd` is used, and with neither the check
stays out of the way (fail-open, C10) -- it never guesses a root.

Policy (C2): casan-policies.yaml -> write_scope (project-tunable: enabled, extra_allowed,
allow_claude_memory, detect_new_entries) and .harness/control/write-scope.json (the
shell verb table). stdlib only.
"""
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True
import harness_handoff as HH  # noqa: E402  (casan-policies block reader)

DEFAULTS = {
    "enabled": True,
    "allow_claude_memory": True,
    "detect_new_entries": True,
    "extra_allowed": [],
}

FILE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
SHELL_TOOLS = {"Bash", "PowerShell"}
NULL_SINKS = {"/dev/null", "nul", "$null", "nul:", "/dev/stdout", "/dev/stderr"}

# Built-in verb table, used when .harness/control/write-scope.json is missing.
DEFAULT_VERBS = {
    "all_args": ["mkdir", "md", "new-item", "ni", "rmdir", "rd", "rm", "del", "erase", "remove-item", "ri",
                 "touch", "out-file", "set-content", "sc", "add-content", "ac", "tee", "tee-object",
                 "export-csv", "export-clixml", "new-temporaryfile", "truncate"],
    "last_arg": ["cp", "copy", "copy-item", "cpi", "mv", "move", "move-item", "mi", "ln", "install", "rsync",
                 "robocopy", "xcopy", "scp"],
    "named_params": ["-destination", "-destinationpath", "-outfile", "-filepath", "-path", "-literalpath",
                     "-outputpath", "-o", "--output", "-c", "--directory", "--basetemp", "--prefix", "--target",
                     "-t", "--target-directory", "/d"],
    "git_subcommands": {"clone": "last_positional", "worktree add": "first_positional",
                        "archive": "named", "init": "first_positional"},
    "script_extensions": [".ps1", ".psm1", ".sh", ".bash", ".cmd", ".bat"],
}

_cache = {}


# ---- config ---------------------------------------------------------------------

def effective_config(root):
    cfg = dict(DEFAULTS)
    try:
        got = HH.read_config(root, "write_scope") or {}
    except Exception:  # noqa: BLE001
        got = {}
    cfg.update({k: v for k, v in got.items() if v is not None})
    if not isinstance(cfg.get("extra_allowed"), list):
        cfg["extra_allowed"] = []
    return cfg


def verb_table(root):
    path = os.path.join(root, ".harness", "control", "write-scope.json")
    try:
        m = os.path.getmtime(path)
    except OSError:
        return DEFAULT_VERBS
    hit = _cache.get(("verbs", path))
    if hit and hit[0] == m:
        return hit[1]
    try:
        with open(path, encoding="utf-8-sig") as f:
            data = json.load(f)
        table = dict(DEFAULT_VERBS)
        for k in DEFAULT_VERBS:
            if k in data:
                table[k] = data[k]
    except (OSError, ValueError):
        table = DEFAULT_VERBS
    _cache[("verbs", path)] = (m, table)
    return table


# ---- paths --------------------------------------------------------------------------

def _norm(p):
    return os.path.normcase(os.path.normpath(p))


def _real(p):
    """Resolve junctions/symlinks of the longest existing prefix; keep the rest as is."""
    p = os.path.abspath(p)
    rest = []
    cur = p
    for _ in range(64):
        if os.path.exists(cur):
            break
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        rest.append(os.path.basename(cur))
        cur = parent
    try:
        base = os.path.realpath(cur)
    except OSError:
        base = cur
    for part in reversed(rest):
        base = os.path.join(base, part)
    return base


def inside(path, root):
    a, b = _norm(_real(path)), _norm(_real(root))
    return a == b or a.startswith(b.rstrip("\\/") + os.sep)


def project_key(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def _transcript_key(transcript_path):
    """The <key> directory right under .claude/projects/ in a transcript path."""
    if not transcript_path:
        return None
    parts = re.split(r"[\\/]+", str(transcript_path))
    for i, seg in enumerate(parts[:-1]):
        if seg.lower() == "projects" and i > 0 and parts[i - 1].lower() == ".claude":
            return parts[i + 1] if i + 1 < len(parts) - 1 else None
    return None


def decode_key(key, hint_roots=()):
    """Find the existing directory whose project_key() is `key`. Hints first (cheap), then
    a bounded walk of the real tree from the drive the key names. None when not found."""
    if not key:
        return None
    hit = _cache.get(("key", key))
    if hit is not None:
        return hit or None
    for h in hint_roots:
        cur = h
        for _ in range(12):
            if cur and project_key(os.path.abspath(cur)) == key:
                _cache[("key", key)] = os.path.abspath(cur)
                return os.path.abspath(cur)
            parent = os.path.dirname(cur) if cur else ""
            if not parent or parent == cur:
                break
            cur = parent
    found = None
    m = re.match(r"^([A-Za-z])--(.*)$", key)
    if m and os.name == "nt":
        found = _walk(m.group(1).upper() + ":\\", m.group(2))
    elif key.startswith("-"):
        found = _walk("/", key[1:])
    _cache[("key", key)] = found or ""
    return found


def _walk(base, rest, depth=0):
    if rest == "":
        return base
    if depth > 12:
        return None
    try:
        names = os.listdir(base)
    except OSError:
        return None
    for n in sorted(names, key=len, reverse=True):
        k = project_key(n)
        if rest == k or rest.startswith(k + "-"):
            p = os.path.join(base, n)
            if not os.path.isdir(p):
                continue
            nxt = rest[len(k) + 1:] if rest != k else ""
            got = _walk(p, nxt, depth + 1)
            if got:
                return got
    return None


def granted_root(payload, cwd_root=None):
    """(root, source) -- the project folder this session was granted (C13: with its source)."""
    key = _transcript_key(payload.get("transcript_path"))
    hints = [h for h in (cwd_root, payload.get("cwd")) if h]
    if key:
        got = decode_key(key, hints)
        if got:
            return got, "transcript key %s" % key
    if cwd_root:
        return cwd_root, "cwd (harness root of %s)" % payload.get("cwd")
    return None, "unknown"


def allowed_roots(root, payload, cfg):
    roots = [root]
    if cfg.get("allow_claude_memory") is not False:
        key = _transcript_key(payload.get("transcript_path"))
        if key:
            tp = str(payload.get("transcript_path"))
            idx = re.split(r"[\\/]+", tp)
            base = None
            for i in range(len(idx) - 1):
                if idx[i].lower() == ".claude" and idx[i + 1].lower() == "projects":
                    base = os.sep.join(idx[: i + 2])
                    if tp.startswith(("/", "\\")) and not base.startswith(os.sep):
                        base = os.sep + base
                    break
            if base:
                roots.append(os.path.join(base, key, "memory"))
    for extra in cfg.get("extra_allowed") or []:
        e = expand(str(extra), root)
        if e:
            roots.append(e if os.path.isabs(e) else os.path.join(root, e))
    return roots


# ---- expansion ----------------------------------------------------------------------

_ENV_RX = [
    (re.compile(r"\$env:([A-Za-z_][A-Za-z0-9_]*)", re.I), lambda m: os.environ.get(m.group(1).upper()) or os.environ.get(m.group(1))),
    (re.compile(r"%([A-Za-z_][A-Za-z0-9_]*)%"), lambda m: os.environ.get(m.group(1).upper()) or os.environ.get(m.group(1))),
    (re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"), lambda m: os.environ.get(m.group(1))),
    (re.compile(r"\$(HOME|TMPDIR|TEMP|TMP|USERPROFILE|LOCALAPPDATA|APPDATA)\b"), lambda m: os.environ.get(m.group(1)) or (os.path.expanduser("~") if m.group(1) == "HOME" else None)),
]


def expand(token, cwd, variables=None):
    """A path token -> absolute path, or None when it cannot be known statically."""
    t = token.strip().strip("'\"")
    if not t or t.startswith("-"):
        return None
    if t.lower() in NULL_SINKS:
        return None
    if variables:
        def sub(m):
            v = variables.get(m.group(1).lower())
            return v if v is not None else m.group(0)
        t = re.sub(r"\$(?!env:)\{?([A-Za-z_][A-Za-z0-9_]*)\}?", sub, t)
    for rx, fn in _ENV_RX:
        t = rx.sub(lambda m: fn(m) if fn(m) is not None else m.group(0), t)
    if os.name != "nt" and "\\" in t:
        # pwsh on Linux/macOS accepts '\' as a separator (`.\x.ps1`); without this a
        # PowerShell-style path was a different file name and its script went unread
        # (server CI on Linux, 15-11).
        t = t.replace("\\", "/")
    if t.startswith("~"):
        t = os.path.expanduser(t)
    if "$" in t or "%" in t or "`" in t:
        return None  # an unresolved variable: unknown, never guess (C13)
    if "://" in t or re.match(r"^[\w.-]+@[\w.-]+:", t) or re.match(r"^[\w.-]+:[^\\/]", t) and not re.match(r"^[A-Za-z]:", t):
        return None  # URL, scp/ssh remote (user@host:path, host:path) -- not a local write
    if os.name == "nt":
        m = re.match(r"^/([A-Za-z])(/.*)?$", t)          # Git Bash /c/Users -> C:\Users
        if m:
            t = m.group(1).upper() + ":" + (m.group(2) or "/")
        elif t.startswith("/tmp"):
            t = os.environ.get("TEMP", "C:\\Temp") + t[4:]
    if os.path.isabs(t) or re.match(r"^[A-Za-z]:", t) or t.startswith("\\\\"):
        return os.path.normpath(t)
    return os.path.normpath(os.path.join(cwd, t))


# ---- shell parsing ------------------------------------------------------------------

_SPLIT = re.compile(r"(?:\r?\n|;|&&|\|\||\||(?<![<>&0-9*])&(?![>&]))")
_REDIRECT = re.compile(r"(?:^|[\s(])(?:[0-9*]?>>?|>\|)\s*(\"[^\"]*\"|'[^']*'|[^\s;&|)]+)")
_ASSIGN_PS = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s;]+)")
_ASSIGN_SH = re.compile(r"(?:^|[\s;])(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(\"[^\"]*\"|'[^']*'|[^\s;&|]+)")


def _tokens(segment):
    out = []
    for m in re.finditer(r"\"[^\"]*\"|'[^']*'|[^\s]+", segment):
        out.append(m.group(0))
    return out


def _variables(text, cwd):
    vars_ = {}
    for rx in (_ASSIGN_PS, _ASSIGN_SH):
        for m in rx.finditer(text):
            val = m.group(2).strip().strip("'\"")
            if "$" in val and not val.lower().startswith("$env:"):
                continue
            vars_[m.group(1).lower()] = val
    return vars_


_RUNNERS_FILE = {"powershell", "pwsh"}          # -File <script>
_RUNNERS_FIRST = {"bash", "sh", "zsh", "dash"}  # first non-flag argument is the script


def _executed_scripts(verb, verb_tok, args):
    """The tokens of this command segment that name a script being EXECUTED."""
    out = [verb_tok]                             # `.\x.ps1`, `./x.sh`, `& x`, `. x` (prefix stripped)
    low = [a.lower() for a in args]
    if verb in _RUNNERS_FILE:
        for i, a in enumerate(low):
            if a in ("-file", "-f") and i + 1 < len(args):
                out.append(args[i + 1])
                break
            if a in ("-command", "-c", "-encodedcommand", "-ec"):
                break
    elif verb in _RUNNERS_FIRST:
        for i, a in enumerate(args):
            if a == "-c":
                break
            if not a.startswith("-"):
                out.append(a)
                break
    elif verb == "cmd":
        for i, a in enumerate(low):
            if a in ("/c", "/k") and i + 1 < len(args):
                out.append(args[i + 1])
                break
    return out


def write_targets(command, cwd, table, depth=0, _seen=None):
    """[(verb, raw_token, absolute_path)] the command writes, as far as patterns can tell."""
    out = []
    if not command:
        return out
    variables = _variables(command, cwd)
    cur = cwd
    all_args = {v.lower() for v in table.get("all_args", [])}
    last_arg = {v.lower() for v in table.get("last_arg", [])}
    named = {v.lower() for v in table.get("named_params", [])}
    script_ext = tuple(e.lower() for e in table.get("script_extensions", []))
    _seen = _seen if _seen is not None else set()

    for seg in _SPLIT.split(command):
        seg = seg.strip()
        if not seg:
            continue
        for m in _REDIRECT.finditer(seg):
            tok = m.group(1)
            if tok.startswith("&"):
                continue
            p = expand(tok, cur, variables)
            if p:
                out.append((">", tok, p))
        toks = _tokens(seg)
        if not toks:
            continue
        i = 0
        while i < len(toks) and (toks[i] in ("&", ".", "sudo", "call", "time", "nohup", "exec")
                                 or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[i])
                                 or re.match(r"^\$[A-Za-z_][A-Za-z0-9_]*$", toks[i]) and len(toks) > i + 1 and toks[i + 1] == "="):
            i += 3 if (re.match(r"^\$", toks[i]) and len(toks) > i + 1 and toks[i + 1] == "=") else 1
        if i >= len(toks):
            continue
        verb_tok = toks[i].strip("'\"")
        verb = os.path.basename(verb_tok.replace("\\", "/")).lower()
        if verb.endswith(".exe"):
            verb = verb[:-4]
        args = toks[i + 1:]
        # cd / Set-Location moves the base for relative targets later in the command
        if verb in ("cd", "set-location", "sl", "chdir", "pushd", "push-location"):
            if args:
                p = expand(args[-1], cur, variables)
                if p:
                    cur = p
            continue
        flagvals = []
        positional = []
        j = 0
        while j < len(args):
            a = args[j]
            low = a.lower()
            if "=" in a and low.split("=", 1)[0] in named:
                flagvals.append(a.split("=", 1)[1])
            elif low in named and j + 1 < len(args):
                flagvals.append(args[j + 1])
                j += 1
            elif not a.startswith("-") or re.match(r"^-?\d", a):
                positional.append(a)
            j += 1
        def add(tok):
            p = expand(tok, cur, variables)
            if p:
                out.append((verb, tok, p))
        if verb in all_args:
            for t in positional + flagvals:
                add(t)
        elif verb in last_arg:
            if verb in ("robocopy", "xcopy") and len(positional) >= 2:
                add(positional[1])
            elif flagvals:
                for t in flagvals:
                    add(t)
            elif len(positional) >= 2:
                add(positional[-1])
        elif verb == "git" and positional:
            sub = positional[0].lower()
            if sub == "clone" and len(positional) >= 3:
                add(positional[-1])
            elif sub == "worktree" and len(positional) >= 3 and positional[1].lower() == "add":
                add(positional[2])
            elif sub == "init" and len(positional) >= 2:
                add(positional[1])
            for t in flagvals:
                add(t)
        elif verb in ("tar", "unzip", "7z", "expand-archive", "compress-archive", "curl", "wget",
                      "invoke-webrequest", "iwr", "pytest", "python", "py", "python3", "pip", "npm", "uv"):
            for t in flagvals:
                add(t)
        # A script file the command RUNS: read it and apply the same patterns (depth 1).
        # Only when it is executed -- `.\x.ps1`, `& x.ps1`, `. x.ps1`, `./x.sh`,
        # `powershell|pwsh -File x`, `bash|sh x`, `cmd /c x`. A script merely NAMED as an
        # argument (Remove-Item, Test-Path, Get-Content, git add, cat...) is not read:
        # reading it denied `Remove-Item .\probe.ps1` because of what the file would
        # have done if run (false positive reported by Ops 15-11, C14).
        if depth == 0:
            for t in _executed_scripts(verb, verb_tok, args):
                tt = t.strip("'\"")
                if tt.lower().endswith(script_ext):
                    sp = expand(tt, cur, variables)
                    if sp and os.path.isfile(sp) and _norm(sp) not in _seen:
                        _seen.add(_norm(sp))
                        try:
                            if os.path.getsize(sp) <= 512 * 1024:
                                with open(sp, encoding="utf-8-sig", errors="replace") as f:
                                    body = f.read()
                                for v, tok, p in write_targets(body, os.path.dirname(sp), table, 1, _seen):
                                    out.append(("%s (in %s)" % (v, os.path.basename(sp)), tok, p))
                        except OSError:
                            pass
    return out


# ---- verdicts -----------------------------------------------------------------------

def _outside(paths, roots):
    return [p for p in paths if not any(inside(p, r) for r in roots)]


def _deny_reason(what, outside, root, roots, source):
    shown = "; ".join(outside[:3]) + (" (+%d)" % (len(outside) - 3) if len(outside) > 3 else "")
    return ("C17 write scope: %s ghi ra NGOAI thu muc du an duoc cap (%s) -> %s. "
            "Chi duoc ghi trong: %s. File nhap/tam: dat trong du an (.harness/tmp hoac thu muc da gitignore), "
            "khong dung %%TEMP%% hay goc o dia. Neu that su can ghi ra ngoai: nguoi van hanh tu chay, "
            "hoac them duong dan vao casan-policies.yaml -> write_scope.extra_allowed (nguon goc du an: %s)."
            % (what, root, shown, ", ".join(roots), source))


def decide_pre(payload, cwd_root):
    """{"decision": "allow"|"deny", "reason", "label", "targets"}"""
    tool = str(payload.get("tool_name") or payload.get("tool") or "")
    if tool not in FILE_TOOLS and tool not in SHELL_TOOLS:
        return {"decision": "allow"}
    root, source = granted_root(payload, cwd_root)
    if not root:
        return {"decision": "allow", "reason": "granted root unknown"}
    cfg = effective_config(root)
    if cfg.get("enabled") is False:
        return {"decision": "allow", "reason": "write_scope.enabled: false"}
    roots = allowed_roots(root, payload, cfg)
    ti = payload.get("tool_input") or payload.get("input") or {}
    if not isinstance(ti, dict):
        ti = {}
    cwd = payload.get("cwd") or root
    if tool in FILE_TOOLS:
        target = next((str(ti[k]) for k in ("file_path", "notebook_path", "path") if ti.get(k)), "")
        if not target:
            return {"decision": "allow"}
        p = target if os.path.isabs(target) else os.path.join(cwd, target)
        out = _outside([p], roots)
        if out:
            return {"decision": "deny", "label": "C17:write-scope", "targets": out,
                    "reason": _deny_reason(tool, out, root, roots, source)}
        return {"decision": "allow"}
    cmd = ti.get("command") or ti.get("script") or ""
    if not isinstance(cmd, str) or not cmd.strip():
        return {"decision": "allow"}
    found = write_targets(cmd, cwd, verb_table(root))
    out = _outside([p for _, _, p in found], roots)
    if out:
        verbs = sorted({v for v, _, p in found if p in out})
        return {"decision": "deny", "label": "C17:write-scope", "targets": out,
                "reason": _deny_reason("lenh shell (%s)" % ", ".join(verbs), out, root, roots, source)}
    return {"decision": "allow"}


# ---- detection after a shell command -------------------------------------------------

_snapshots = {}


def watch_dirs(root):
    root = os.path.abspath(root)
    drive = os.path.splitdrive(root)[0]
    dirs = []
    if drive:
        dirs.append(drive + os.sep)
    else:
        dirs.append(os.sep)
    parent = os.path.dirname(root)
    if parent and _norm(parent) not in {_norm(d) for d in dirs}:
        dirs.append(parent)
    return dirs


def _listing(d):
    try:
        return set(os.listdir(d))
    except OSError:
        return None


def _snap_key(payload):
    return payload.get("tool_use_id") or "%s|%s" % (payload.get("session_id"), json.dumps(payload.get("tool_input"), sort_keys=True)[:200])


def before_shell(payload, cwd_root):
    tool = str(payload.get("tool_name") or "")
    if tool not in SHELL_TOOLS:
        return
    root, _src = granted_root(payload, cwd_root)
    if not root:
        return
    if effective_config(root).get("detect_new_entries") is False:
        return
    snap = {d: _listing(d) for d in watch_dirs(root)}
    _snapshots[_snap_key(payload)] = (time.time(), root, snap)
    if len(_snapshots) > 500:  # a lost Post must not grow this forever
        for k in sorted(_snapshots, key=lambda k: _snapshots[k][0])[:250]:
            _snapshots.pop(k, None)


def after_shell(payload):
    """New entries that appeared in a watched directory while the command ran, or []."""
    hit = _snapshots.pop(_snap_key(payload), None)
    if not hit:
        return []
    _t0, root, snap = hit
    new = []
    for d, before in snap.items():
        if before is None:
            continue
        now = _listing(d)
        if not now:
            continue
        for n in sorted(now - before):
            p = os.path.join(d, n)
            if inside(p, root):
                continue
            new.append(p)
    return new


def detection_message(new, root):
    return ("C17 write scope: trong luc lenh vua chay, xuat hien muc MOI ngoai thu muc du an %s: %s. "
            "Neu do la cua phien nay: xoa no ngay va lam lai ben trong du an (.harness/tmp hoac thu muc da gitignore). "
            "Da ghi su kien bao mat." % (root, "; ".join(new[:5])))


if __name__ == "__main__":  # manual probe: echo '<hook json>' | python harness_write_scope.py
    data = json.loads(sys.stdin.buffer.read().decode("utf-8-sig") or "{}")
    print(json.dumps(decide_pre(data, None), ensure_ascii=False, indent=1))
