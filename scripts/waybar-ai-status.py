#!/usr/bin/env python3
"""Waybar custom module: AI agent activity + usage (compact icons, rich tooltip).

Local signals for work-in-progress; Cursor usage via DashboardService (cached);
ChatGPT/Codex rate limits from the newest ~/.codex rollout.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

ACTIVE_GRACE_S = 120.0
USAGE_CACHE_TTL_S = 600.0
CURSOR_USAGE_URL = (
    "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
)
USER_QUERY_RE = re.compile(r"<user_query>\s*(.*?)\s*</user_query>", re.S)
SKY_RE = re.compile(r"sky_linux")

# Nerd Font glyphs (JetBrainsMono Nerd Font on the bar).
ICON_CURSOR = "\ue795"
ICON_CHATGPT = "\uf085"
ICON_GROK = "\uf6f0"
ICON_OPENCODE = "\uf120"

COLOR_ACTIVE = "#33c5c5"
COLOR_IDLE = "#6b7785"
COLOR_WARN = "#e5c07b"
COLOR_CRIT = "#e06c75"


def runtime_dir() -> Path:
    env = os.environ.get("XDG_RUNTIME_DIR")
    if env:
        return Path(env)
    return Path(f"/run/user/{os.getuid()}")


def home() -> Path:
    return Path.home()


def usage_cache_path() -> Path:
    return runtime_dir() / "ai-status-usage-cache.json"


def read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def write_json(path: Path, obj: dict) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(obj, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)
    except OSError:
        pass


def _read_tail(path: Path, max_bytes: int = 200_000) -> str:
    try:
        size = path.stat().st_size
        with path.open("rb") as f:
            if size > max_bytes:
                f.seek(size - max_bytes)
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def proc_cmdlines() -> list[str]:
    out: list[str] = []
    try:
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                raw = (entry / "cmdline").read_bytes()
            except OSError:
                continue
            if not raw:
                continue
            out.append(raw.replace(b"\0", b" ").decode("utf-8", "replace"))
    except OSError:
        pass
    return out


def any_proc(pred) -> bool:
    for cmd in proc_cmdlines():
        if pred(cmd):
            return True
    return False


@dataclass
class AgentStatus:
    key: str
    label: str
    icon: str
    running: bool = False
    working: bool = False
    work: str = ""
    usage_line: str = ""
    usage_pct: float | None = None
    extras: list[str] = field(default_factory=list)


def truncate(text: str, n: int = 72) -> str:
    text = " ".join(text.split())
    if len(text) <= n:
        return text
    return text[: n - 1] + "…"


def cursor_access_token() -> str | None:
    db = home() / ".config" / "Cursor" / "User" / "globalStorage" / "state.vscdb"
    if not db.is_file():
        return None
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        try:
            row = con.execute(
                "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'"
            ).fetchone()
        finally:
            con.close()
    except sqlite3.Error:
        return None
    if not row or not row[0]:
        return None
    return str(row[0])


def cursor_plan() -> str:
    db = home() / ".config" / "Cursor" / "User" / "globalStorage" / "state.vscdb"
    if not db.is_file():
        return ""
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        try:
            row = con.execute(
                "SELECT value FROM ItemTable WHERE key='cursorAuth/stripeMembershipType'"
            ).fetchone()
        finally:
            con.close()
    except sqlite3.Error:
        return ""
    return str(row[0]) if row and row[0] else ""


def fetch_cursor_usage() -> dict | None:
    token = cursor_access_token()
    if not token:
        return None
    req = urllib.request.Request(
        CURSOR_USAGE_URL,
        data=b"{}",
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "User-Agent": "waybar-ai-status/0.1",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8", "replace"))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError):
        return None


def load_cursor_usage_cached() -> dict | None:
    cache = usage_cache_path()
    cached = read_json(cache)
    now = time.time()
    if cached and (now - float(cached.get("fetched_at", 0))) < USAGE_CACHE_TTL_S:
        return cached.get("cursor")
    fresh = fetch_cursor_usage()
    if fresh is not None:
        write_json(
            cache,
            {
                "fetched_at": now,
                "cursor": fresh,
                "codex": (cached or {}).get("codex"),
            },
        )
        return fresh
    return (cached or {}).get("cursor")


def newest_codex_rollout() -> Path | None:
    sessions = home() / ".codex" / "sessions"
    if not sessions.is_dir():
        return None
    best: Path | None = None
    best_m = 0.0
    try:
        for path in sessions.rglob("rollout-*.jsonl"):
            try:
                m = path.stat().st_mtime
            except OSError:
                continue
            if m >= best_m:
                best_m = m
                best = path
    except OSError:
        return None
    return best


def extract_codex_rate_limits(path: Path | None) -> dict | None:
    if path is None:
        return None
    best = None
    for line in _read_tail(path, 250_000).splitlines():
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        payload = obj.get("payload") if isinstance(obj, dict) else None
        if not isinstance(payload, dict):
            continue
        rl = payload.get("rate_limits")
        if isinstance(rl, dict) and "primary" in rl:
            best = rl
    return best


def extract_codex_work(path: Path | None) -> str:
    if path is None:
        return ""
    last = ""
    for line in _read_tail(path, 120_000).splitlines():
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        payload = obj.get("payload") if isinstance(obj, dict) else None
        if not isinstance(payload, dict):
            continue
        ptype = payload.get("type")
        if ptype == "message" and payload.get("role") == "assistant":
            for part in payload.get("content") or []:
                if isinstance(part, dict) and part.get("type") == "output_text":
                    text = (part.get("text") or "").strip()
                    if text:
                        last = text
        elif ptype in ("custom_tool_call", "function_call"):
            name = payload.get("name") or "tool"
            last = f"▸ {name}"
        elif ptype == "reasoning":
            for item in payload.get("summary") or []:
                if isinstance(item, dict):
                    t = (item.get("text") or "").strip()
                    if t:
                        last = f"… {t}"
    return truncate(last)


def chatgpt_active_execs() -> bool:
    d = home() / ".codex" / "node_repl" / "active_execs"
    if not d.is_dir():
        return False
    try:
        return any(p.name not in (".", "..") for p in d.iterdir())
    except OSError:
        return False


def scan_cursor_transcript(now: float) -> tuple[float, str, Path | None]:
    root = home() / ".cursor" / "projects"
    if not root.is_dir():
        return 0.0, "", None
    best_m = 0.0
    best_path: Path | None = None
    best_title = ""
    try:
        for project in root.iterdir():
            transcripts = project / "agent-transcripts"
            if not transcripts.is_dir():
                continue
            for jsonl in transcripts.rglob("*.jsonl"):
                try:
                    m = jsonl.stat().st_mtime
                except OSError:
                    continue
                if now - m > ACTIVE_GRACE_S * 3:
                    continue
                if m >= best_m:
                    best_m = m
                    best_path = jsonl
    except OSError:
        pass
    if best_path is None:
        return 0.0, "", None
    title = ""
    last_tool = ""
    for line in _read_tail(best_path, 160_000).splitlines():
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        role = obj.get("role")
        msg = obj.get("message") or {}
        content = msg.get("content") or []
        if not isinstance(content, list):
            continue
        if role == "user":
            for part in content:
                if not isinstance(part, dict) or part.get("type") != "text":
                    continue
                m = USER_QUERY_RE.search(part.get("text") or "")
                if m:
                    title = truncate(m.group(1).strip().splitlines()[0])
        elif role == "assistant":
            for part in content:
                if not isinstance(part, dict):
                    continue
                if part.get("type") == "tool_use":
                    last_tool = str(part.get("name") or "tool")
    work = title or (f"▸ {last_tool}" if last_tool else "")
    return best_m, work, best_path


def pct_color(pct: float | None) -> str:
    if pct is None:
        return COLOR_IDLE
    if pct >= 95:
        return COLOR_CRIT
    if pct >= 80:
        return COLOR_WARN
    return COLOR_ACTIVE


def format_pct(pct: float | None) -> str:
    if pct is None:
        return ""
    if pct >= 10:
        return f"{int(round(pct))}"
    return f"{pct:.0f}" if pct == int(pct) else f"{pct:.1f}".rstrip("0").rstrip(".")


def span(text: str, color: str) -> str:
    esc = (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )
    return f'<span foreground="{color}">{esc}</span>'


def build_cursor(now: float) -> AgentStatus:
    st = AgentStatus(key="cursor", label="Cursor", icon=ICON_CURSOR)
    st.running = any_proc(
        lambda c: ("/lib/cursor/cursor" in c or c.strip().startswith("cursor "))
        and "--type=" not in c
    )
    mtime, work, _path = scan_cursor_transcript(now)
    if mtime and (now - mtime) <= ACTIVE_GRACE_S:
        st.working = True
        st.work = work or "エージェント稼働中"
    elif work and mtime and (now - mtime) <= 3600:
        st.work = work
    plan = cursor_plan()
    if plan:
        st.extras.append(plan)
    usage = load_cursor_usage_cached()
    if isinstance(usage, dict):
        plan_usage = usage.get("planUsage") or {}
        total = plan_usage.get("totalPercentUsed")
        auto = plan_usage.get("autoPercentUsed")
        api = plan_usage.get("apiPercentUsed")
        try:
            st.usage_pct = float(total) if total is not None else None
        except (TypeError, ValueError):
            st.usage_pct = None
        bits = []
        if st.usage_pct is not None:
            bits.append(f"合計 {st.usage_pct:.0f}%")
        if auto is not None:
            bits.append(f"auto {float(auto):.0f}%")
        if api is not None:
            bits.append(f"API {float(api):.0f}%")
        msg = usage.get("displayMessage") or usage.get("autoModelSelectedDisplayMessage")
        if bits:
            st.usage_line = " / ".join(bits)
        if msg:
            st.extras.append(str(msg))
    return st


def build_chatgpt(now: float) -> AgentStatus:
    st = AgentStatus(key="chatgpt", label="ChatGPT", icon=ICON_CHATGPT)
    st.running = any_proc(
        lambda c: ("/lib/chatgpt/ChatGPT" in c or "ChatGPT" in c.split(" ")[0])
        and "--type=" not in c
    )
    rollout = newest_codex_rollout()
    rollout_m = 0.0
    if rollout is not None:
        try:
            rollout_m = rollout.stat().st_mtime
        except OSError:
            rollout_m = 0.0
    hot = chatgpt_active_execs() or any_proc(lambda c: SKY_RE.search(c) is not None)
    if hot or (rollout_m and (now - rollout_m) <= ACTIVE_GRACE_S):
        st.working = True
        st.work = extract_codex_work(rollout) or "エージェント稼働中"
    elif rollout_m and (now - rollout_m) <= 3600:
        st.work = extract_codex_work(rollout)
    rl = extract_codex_rate_limits(rollout)
    if isinstance(rl, dict):
        primary = rl.get("primary") or {}
        secondary = rl.get("secondary") or {}
        plan = rl.get("plan_type")
        if plan:
            st.extras.append(str(plan))
        try:
            p = float(primary.get("used_percent"))
            st.usage_pct = p
        except (TypeError, ValueError):
            p = None
        try:
            s = float(secondary.get("used_percent"))
        except (TypeError, ValueError):
            s = None
        bits = []
        if p is not None:
            mins = primary.get("window_minutes")
            label = f"{mins}m" if mins else "短"
            bits.append(f"{label} {p:.0f}%")
        if s is not None:
            mins = secondary.get("window_minutes")
            label = f"{int(mins) // 1440}d" if mins and mins >= 1440 else "週"
            bits.append(f"{label} {s:.0f}%")
        if bits:
            st.usage_line = " / ".join(bits)
            # Prefer the higher of the two windows for compact % + warn color.
            vals = [v for v in (p, s) if v is not None]
            if vals:
                st.usage_pct = max(vals)
    return st


def build_grok() -> AgentStatus:
    st = AgentStatus(key="grok", label="Grok", icon=ICON_GROK)
    st.running = any_proc(
        lambda c: ("grok-bot" in c or "/lib/grok" in c or "Grok Bot" in c)
        and "--type=" not in c
    )
    if st.running:
        st.working = True
        st.work = "デスクトップ起動中"
    return st


def build_opencode() -> AgentStatus:
    st = AgentStatus(key="opencode", label="OpenCode", icon=ICON_OPENCODE)
    st.running = any_proc(
        lambda c: re.search(r"(^|[/\s])opencode(\s|$)", c) is not None
        and "waybar-ai-status" not in c
    )
    if st.running:
        st.working = True
        st.work = "ターミナルエージェント"
        log = home() / ".local" / "share" / "opencode" / "log" / "opencode.log"
        if log.is_file():
            try:
                age = time.time() - log.stat().st_mtime
                st.extras.append(f"log {int(age)}s ago")
            except OSError:
                pass
    return st


def compact_block(st: AgentStatus) -> list[str]:
    """One icon (+ optional %) for the narrow vertical bar."""
    if st.working:
        color = COLOR_ACTIVE
    elif st.usage_pct is not None and st.usage_pct >= 80:
        color = pct_color(st.usage_pct)
    elif st.running:
        color = COLOR_ACTIVE
    else:
        color = COLOR_IDLE
    lines = [span(st.icon, color)]
    pct = format_pct(st.usage_pct)
    if pct != "":
        lines.append(span(pct, pct_color(st.usage_pct)))
    elif st.working:
        lines.append(span("●", COLOR_ACTIVE))
    return lines


def tooltip_block(st: AgentStatus) -> list[str]:
    if st.working:
        mark = "● 作業中"
    elif st.running:
        mark = "○ 起動中"
    else:
        mark = "○ 待機"
    lines = [f"{st.label}  {mark}"]
    if st.work:
        lines.append(f"  {st.work}")
    if st.usage_line:
        lines.append(f"  使用量 {st.usage_line}")
    for extra in st.extras:
        lines.append(f"  {extra}")
    return lines


def main() -> int:
    now = time.time()
    agents = [
        build_cursor(now),
        build_chatgpt(now),
        build_grok(),
        build_opencode(),
    ]
    # Always show Cursor + ChatGPT; Grok/OpenCode when running (or always if any busy).
    show = []
    any_busy = any(a.working for a in agents)
    for a in agents:
        if a.key in ("cursor", "chatgpt") or a.running or a.working or any_busy:
            show.append(a)
    if not show:
        show = agents[:2]

    text_lines: list[str] = []
    for a in show:
        text_lines.extend(compact_block(a))
    tip_lines: list[str] = []
    for a in agents:
        tip_lines.extend(tooltip_block(a))
        tip_lines.append("")
    while tip_lines and tip_lines[-1] == "":
        tip_lines.pop()

    classes = ["ai"]
    if any(a.working for a in agents):
        classes.append("busy")
    elif any(a.running for a in agents):
        classes.append("running")
    else:
        classes.append("idle")
    max_pct = max((a.usage_pct for a in agents if a.usage_pct is not None), default=None)
    if max_pct is not None and max_pct >= 95:
        classes.append("critical")
    elif max_pct is not None and max_pct >= 80:
        classes.append("warning")

    obj = {
        "text": "\n".join(text_lines),
        "tooltip": "\n".join(tip_lines),
        "class": " ".join(classes),
        "alt": "busy" if "busy" in classes else "idle",
    }
    print(json.dumps(obj, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
