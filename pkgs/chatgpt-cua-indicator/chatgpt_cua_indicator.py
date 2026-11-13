#!/usr/bin/env python3
"""Sway/wlroots overlay while an agent is driving the screen / browser.

Only screen ops — not ordinary chat / think turns:
  ChatGPT: Computer Use helpers (sky_linux / node_repl active_execs)
  Cursor: recent browser_* / cursor-ide-browser tool_use in agent transcripts

Shows a click-through edge frame, top-center banner, chat panel underneath,
Hide (dismiss HUD only) and Stop buttons. Esc is handled via Sway mode
"agent-screen".
"""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")

from gi.repository import GLib, Gdk, Gtk, GtkLayerShell  # noqa: E402

ACCENT = (0x33 / 255.0, 0x9C / 255.0, 0xFF / 255.0, 1.0)
PILL_BG = (0.043, 0.059, 0.078, 0.92)
PANEL_BG = (0.043, 0.059, 0.078, 0.94)
HIDE_BG = (0.22, 0.28, 0.36, 0.95)
STOP_BG = (0.88, 0.27, 0.35, 0.95)  # soft-ish
EDGE_PX = 4
PILL_PAD_X = 18
PILL_PAD_Y = 10
PILL_TOP = 28
PANEL_W = 560
PANEL_H = 220
PANEL_GAP = 10
PANEL_PAD = 12
BTN_W = 80
BTN_H = 28
BTN_GAP = 8
HINT = "Escで停止"
# Grace after Computer Use helpers vanish (covers brief restarts between actions).
CHAT_HIDE_AFTER_S = 3.0
# Cursor browser tools are bursty; keep HUD up between actions.
CURSOR_BROWSER_GRACE_S = 8.0
# Browser tool must be among the newest transcript lines (not earlier in the turn).
CURSOR_BROWSER_MAX_LINES_AFTER = 8
POLL_MS = 400
CHAT_MAX_CHARS = 1800
SKY_RE = re.compile(r"sky_linux")
BROWSER_TOOL_RE = re.compile(
    r"(?:browser_[a-z0-9_]+|cursor-ide-browser)", re.IGNORECASE
)
# Match home/sway.nix waybar exclusive zones so the HUD covers the full output
# (sway insets overlay surfaces by other layers' exclusive zones otherwise).
WAYBAR_LEFT_PX = 34  # sideBar.width
WAYBAR_BOTTOM_PX = 30  # mainBar.height


def runtime_dir() -> Path:
    env = os.environ.get("XDG_RUNTIME_DIR")
    if env:
        return Path(env)
    return Path(f"/run/user/{os.getuid()}")


def active_path() -> Path:
    return runtime_dir() / "agent-screen" / "active"


def hide_request_path() -> Path:
    return runtime_dir() / "agent-screen" / "hide"


def codex_home() -> Path:
    env = os.environ.get("CODEX_HOME")
    if env:
        return Path(env)
    return Path.home() / ".codex"


def active_execs_dir() -> Path:
    return codex_home() / "node_repl" / "active_execs"


def has_active_execs() -> bool:
    d = active_execs_dir()
    if not d.is_dir():
        return False
    try:
        return any(p.name not in (".", "..") for p in d.iterdir())
    except OSError:
        return False


def sky_linux_running() -> bool:
    try:
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                cmdline = (entry / "cmdline").read_bytes()
            except OSError:
                continue
            text = cmdline.replace(b"\0", b" ").decode("utf-8", "replace")
            if SKY_RE.search(text):
                return True
    except OSError:
        pass
    return False


def chatgpt_active() -> bool:
    """True only while Computer Use helpers are driving the screen."""
    return has_active_execs() or sky_linux_running()


def cursor_projects_root() -> Path:
    return Path.home() / ".cursor" / "projects"


def _read_tail_text(path: Path, max_bytes: int = 256_000) -> str:
    try:
        size = path.stat().st_size
        with path.open("rb") as f:
            if size > max_bytes:
                f.seek(size - max_bytes)
            data = f.read()
        return data.decode("utf-8", "replace")
    except OSError:
        return ""


def _line_is_browser_tool_invocation(line: str) -> bool:
    if not BROWSER_TOOL_RE.search(line):
        return False
    # Require an actual tool invocation, not a prose mention.
    return '"tool_use"' in line or "CallDynamicTool" in line or '"browser_' in line


def _cursor_browser_tool_mtime(path: Path, now: float) -> float | None:
    """mtime if a browser tool_use is still among the newest lines; else None.

    Avoids keeping the HUD up for an old browser call while the agent has moved
    on to ordinary (non-screen) work in the same transcript.
    """
    try:
        mtime = path.stat().st_mtime
    except OSError:
        return None
    if now - mtime > CURSOR_BROWSER_GRACE_S * 3:
        return None
    text = _read_tail_text(path, max_bytes=96_000)
    if not text:
        return None
    lines = text.splitlines()
    last_idx: int | None = None
    for i in range(len(lines) - 1, -1, -1):
        if _line_is_browser_tool_invocation(lines[i]):
            last_idx = i
            break
    if last_idx is None:
        return None
    if (len(lines) - 1 - last_idx) > CURSOR_BROWSER_MAX_LINES_AFTER:
        return None
    if now - mtime > CURSOR_BROWSER_GRACE_S:
        return None
    return mtime


def scan_cursor_browser_activity(
    now: float,
) -> tuple[float, Path | None]:
    """Return (last_browser_tool_mtime, transcript_path) or (0, None)."""
    root = cursor_projects_root()
    if not root.is_dir():
        return 0.0, None
    best_mtime = 0.0
    best_path: Path | None = None
    try:
        for project in root.iterdir():
            transcripts = project / "agent-transcripts"
            if not transcripts.is_dir():
                continue
            for jsonl in transcripts.rglob("*.jsonl"):
                mtime = _cursor_browser_tool_mtime(jsonl, now)
                if mtime is None:
                    continue
                if mtime >= best_mtime:
                    best_mtime = mtime
                    best_path = jsonl
    except OSError:
        pass
    return best_mtime, best_path


def newest_codex_rollout() -> Path | None:
    sessions = codex_home() / "sessions"
    if not sessions.is_dir():
        return None
    best: Path | None = None
    best_mtime = 0.0
    try:
        for path in sessions.rglob("rollout-*.jsonl"):
            try:
                mtime = path.stat().st_mtime
            except OSError:
                continue
            if mtime >= best_mtime:
                best_mtime = mtime
                best = path
    except OSError:
        return None
    return best


def extract_chatgpt_chat(path: Path | None) -> str:
    if path is None:
        return ""
    lines_out: list[str] = []
    for line in _read_tail_text(path).splitlines():
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("type") != "response_item":
            continue
        payload = obj.get("payload") or {}
        ptype = payload.get("type")
        if ptype == "message" and payload.get("role") == "assistant":
            for part in payload.get("content") or []:
                if part.get("type") == "output_text":
                    text = (part.get("text") or "").strip()
                    if text:
                        lines_out.append(text)
        elif ptype == "custom_tool_call":
            name = payload.get("name") or "tool"
            lines_out.append(f"▸ {name}")
        elif ptype == "function_call":
            name = payload.get("name") or "function"
            lines_out.append(f"▸ {name}")
        elif ptype == "reasoning":
            summary = payload.get("summary") or []
            for item in summary:
                if isinstance(item, dict):
                    t = (item.get("text") or "").strip()
                    if t:
                        lines_out.append(f"… {t}")
                elif isinstance(item, str) and item.strip():
                    lines_out.append(f"… {item.strip()}")
    return _trim_chat("\n\n".join(lines_out[-12:]))


def extract_cursor_chat(path: Path | None) -> str:
    if path is None:
        return ""
    lines_out: list[str] = []
    for line in _read_tail_text(path).splitlines():
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        role = obj.get("role")
        msg = obj.get("message") or {}
        content = msg.get("content") or []
        if not isinstance(content, list):
            continue
        if role == "assistant":
            for part in content:
                if not isinstance(part, dict):
                    continue
                if part.get("type") == "text":
                    text = (part.get("text") or "").strip()
                    if text:
                        # Drop huge system dumps; keep readable snippets.
                        if text.startswith("<") and len(text) > 400:
                            continue
                        lines_out.append(text)
                elif part.get("type") == "tool_use":
                    name = part.get("name") or "tool"
                    if BROWSER_TOOL_RE.search(name) or name.startswith("browser_"):
                        lines_out.append(f"▸ {name}")
                    elif name == "CallDynamicTool":
                        inp = part.get("input") or {}
                        ns = str(inp.get("namespace") or "")
                        tool = str(inp.get("toolName") or "")
                        if "browser" in ns or tool.startswith("browser_"):
                            lines_out.append(f"▸ {ns}.{tool}".strip("."))
    return _trim_chat("\n\n".join(lines_out[-12:]))


def _trim_chat(text: str) -> str:
    text = text.strip()
    if len(text) <= CHAT_MAX_CHARS:
        return text
    return "…\n" + text[-CHAT_MAX_CHARS:]


@dataclass
class Activity:
    agent: str  # chatgpt | cursor
    title: str
    chat: str
    score: float  # monotonic-ish; higher = more recent


def swaymsg(*args: str) -> None:
    try:
        subprocess.run(
            ["swaymsg", *args],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


class OverlayWindow(Gtk.Window):
    def __init__(self, monitor: Gdk.Monitor, primary: bool) -> None:
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self._primary = primary
        self._title = "エージェントが操作中"
        self._chat = ""
        self._hide_rect = (0.0, 0.0, 0.0, 0.0)  # x,y,w,h
        self._stop_rect = (0.0, 0.0, 0.0, 0.0)
        self._panel_rect = (0.0, 0.0, 0.0, 0.0)
        self._on_hide = None  # type: ignore
        self._on_stop = None  # type: ignore

        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_accept_focus(False)
        self.set_can_focus(False)

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "agent-screen-hud")
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        GtkLayerShell.set_exclusive_zone(self, 0)
        GtkLayerShell.set_monitor(self, monitor)
        for edge in (
            GtkLayerShell.Edge.TOP,
            GtkLayerShell.Edge.BOTTOM,
            GtkLayerShell.Edge.LEFT,
            GtkLayerShell.Edge.RIGHT,
        ):
            GtkLayerShell.set_anchor(self, edge, True)
        # Negative margins cancel sway's usable-area inset from waybar exclusive
        # zones so the blue frame sits on the true output edges.
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 0)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, 0)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, -WAYBAR_LEFT_PX)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, -WAYBAR_BOTTOM_PX)

        geo = monitor.get_geometry()
        self._width = geo.width
        self._height = geo.height
        self.set_size_request(self._width, self._height)

        self.connect("draw", self._on_draw)
        self.connect("realize", self._on_realize)
        self.connect("size-allocate", self._on_size_allocate)
        self.connect("button-press-event", self._on_button)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)

    def set_content(self, title: str, chat: str) -> None:
        if title == self._title and chat == self._chat:
            return
        self._title = title
        self._chat = chat
        self.queue_draw()

    def _on_realize(self, *_args) -> None:
        self._apply_input_region()

    def _on_size_allocate(self, _widget, allocation) -> None:
        w = int(allocation.width)
        h = int(allocation.height)
        if w < 2 or h < 2:
            return
        if w == self._width and h == self._height:
            return
        self._width = w
        self._height = h
        self.queue_draw()

    def _apply_input_region(self) -> None:
        window = self.get_window()
        if window is None:
            return
        # Click-through everywhere except Hide/Stop on the primary monitor.
        region = cairo.Region()
        if self._primary:
            for box in (self._hide_rect, self._stop_rect):
                x, y, w, h = box
                if w <= 0 or h <= 0:
                    continue
                rect = cairo.RectangleInt(int(x), int(y), int(w), int(h))
                if region.is_empty():
                    region = cairo.Region(rect)
                else:
                    region.union(cairo.Region(rect))
        window.input_shape_combine_region(region, 0, 0)

    @staticmethod
    def _hit(box: tuple[float, float, float, float], x: float, y: float) -> bool:
        bx, by, bw, bh = box
        return bw > 0 and bh > 0 and bx <= x <= bx + bw and by <= y <= by + bh

    def _on_button(self, _widget, event) -> bool:
        if not self._primary:
            return False
        if self._on_hide is not None and self._hit(self._hide_rect, event.x, event.y):
            self._on_hide()
            return True
        if self._on_stop is not None and self._hit(self._stop_rect, event.x, event.y):
            self._on_stop()
            return True
        return False

    def _on_draw(self, _widget, cr: cairo.Context) -> bool:
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        w, h = self._width, self._height
        cr.set_source_rgba(*ACCENT)
        cr.rectangle(0, 0, w, EDGE_PX)
        cr.rectangle(0, h - EDGE_PX, w, EDGE_PX)
        cr.rectangle(0, 0, EDGE_PX, h)
        cr.rectangle(w - EDGE_PX, 0, EDGE_PX, h)
        cr.fill()

        # Status pill (top center)
        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(14)
        title_ext = cr.text_extents(self._title)
        cr.set_font_size(12)
        hint_ext = cr.text_extents(HINT)
        text_w = max(title_ext.width, hint_ext.width)
        pill_w = text_w + PILL_PAD_X * 2
        pill_h = title_ext.height + hint_ext.height + PILL_PAD_Y * 2 + 6
        pill_x = (w - pill_w) / 2
        pill_y = PILL_TOP

        cr.set_source_rgba(*PILL_BG)
        self._rounded_rect(cr, pill_x, pill_y, pill_w, pill_h, 8)
        cr.fill()
        cr.set_source_rgba(*ACCENT)
        cr.set_line_width(2)
        self._rounded_rect(cr, pill_x, pill_y, pill_w, pill_h, 8)
        cr.stroke()

        cr.set_source_rgba(1, 1, 1, 1)
        cr.set_font_size(14)
        cr.move_to(
            pill_x + (pill_w - title_ext.width) / 2,
            pill_y + PILL_PAD_Y + title_ext.height,
        )
        cr.show_text(self._title)

        cr.set_source_rgba(*ACCENT)
        cr.set_font_size(12)
        cr.move_to(
            pill_x + (pill_w - hint_ext.width) / 2,
            pill_y + PILL_PAD_Y + title_ext.height + 6 + hint_ext.height,
        )
        cr.show_text(HINT)

        # Buttons + chat under the banner (primary monitor only).
        if self._primary:
            panel_x = (w - PANEL_W) / 2
            btn_y = pill_y + pill_h + BTN_GAP
            stop_x = panel_x + PANEL_W - BTN_W
            hide_x = stop_x - BTN_GAP - BTN_W
            self._stop_rect = (stop_x, btn_y, BTN_W, BTN_H)
            self._hide_rect = (hide_x, btn_y, BTN_W, BTN_H)

            self._draw_button(cr, hide_x, btn_y, BTN_W, BTN_H, HIDE_BG, "非表示")
            self._draw_button(cr, stop_x, btn_y, BTN_W, BTN_H, STOP_BG, "停止")

            panel_y = btn_y + BTN_H + PANEL_GAP
            self._panel_rect = (panel_x, panel_y, PANEL_W, PANEL_H)

            cr.set_source_rgba(*PANEL_BG)
            self._rounded_rect(cr, panel_x, panel_y, PANEL_W, PANEL_H, 8)
            cr.fill()
            cr.set_source_rgba(*ACCENT)
            cr.set_line_width(1.5)
            self._rounded_rect(cr, panel_x, panel_y, PANEL_W, PANEL_H, 8)
            cr.stroke()

            self._draw_wrapped_text(
                cr,
                self._chat or "（思考・操作ログを待機中…）",
                panel_x + PANEL_PAD,
                panel_y + PANEL_PAD,
                PANEL_W - PANEL_PAD * 2,
                PANEL_H - PANEL_PAD * 2,
            )
            self._apply_input_region()
        else:
            self._hide_rect = (0.0, 0.0, 0.0, 0.0)
            self._stop_rect = (0.0, 0.0, 0.0, 0.0)
            self._apply_input_region()

        return False

    def _draw_button(
        self,
        cr: cairo.Context,
        x: float,
        y: float,
        w: float,
        h: float,
        bg: tuple[float, float, float, float],
        label: str,
    ) -> None:
        cr.set_source_rgba(*bg)
        self._rounded_rect(cr, x, y, w, h, 6)
        cr.fill()
        cr.set_source_rgba(1, 1, 1, 1)
        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(13)
        ext = cr.text_extents(label)
        cr.move_to(x + (w - ext.width) / 2, y + (h + ext.height) / 2)
        cr.show_text(label)

    def _draw_wrapped_text(
        self,
        cr: cairo.Context,
        text: str,
        x: float,
        y: float,
        max_w: float,
        max_h: float,
    ) -> None:
        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        cr.set_font_size(12)
        cr.set_source_rgba(0.9, 0.93, 0.95, 1.0)
        line_h = 16.0
        cy = y + line_h
        # Draw from the end so newest content stays visible.
        raw_lines = text.splitlines() or [text]
        wrapped: list[str] = []
        for raw in raw_lines:
            if not raw:
                wrapped.append("")
                continue
            buf = ""
            for ch in raw:
                trial = buf + ch
                if cr.text_extents(trial).width <= max_w:
                    buf = trial
                else:
                    if buf:
                        wrapped.append(buf)
                    buf = ch
            wrapped.append(buf)
        max_lines = max(1, int(max_h // line_h))
        visible = wrapped[-max_lines:]
        for line in visible:
            if cy > y + max_h:
                break
            cr.move_to(x, cy)
            cr.show_text(line[:500])
            cy += line_h

    @staticmethod
    def _rounded_rect(
        cr: cairo.Context, x: float, y: float, w: float, h: float, r: float
    ) -> None:
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -1.5708, 0)
        cr.arc(x + w - r, y + h - r, r, 0, 1.5708)
        cr.arc(x + r, y + h - r, r, 1.5708, 3.1416)
        cr.arc(x + r, y + r, r, 3.1416, 4.7124)
        cr.close_path()


class IndicatorApp:
    def __init__(self) -> None:
        self._windows: list[OverlayWindow] = []
        self._visible = False
        # User dismissed HUD for the current screen-control session.
        self._dismissed = False
        self._agent = ""
        self._title = ""
        self._chat = ""
        self._last_chatgpt = 0.0
        self._last_cursor = 0.0
        self._cursor_transcript: Path | None = None
        self._started = 0.0
        self._display = Gdk.Display.get_default()
        if self._display is None:
            raise SystemExit("no Gdk display (need a Wayland session)")

        active_execs_dir().mkdir(parents=True, exist_ok=True)
        active_path().parent.mkdir(parents=True, exist_ok=True)
        self._rebuild_windows()
        if hasattr(self._display, "connect"):
            try:
                self._display.connect("monitor-added", lambda *_: self._rebuild_windows())
                self._display.connect(
                    "monitor-removed", lambda *_: self._rebuild_windows()
                )
            except TypeError:
                pass

        GLib.timeout_add(POLL_MS, self._tick)

    def _rebuild_windows(self) -> None:
        for win in self._windows:
            win.destroy()
        self._windows = []
        n = self._display.get_n_monitors()
        for i in range(n):
            mon = self._display.get_monitor(i)
            if mon is None:
                continue
            win = OverlayWindow(mon, primary=(i == 0))
            win._on_hide = self._request_dismiss
            win._on_stop = self._request_stop
            win.set_content(self._title or "エージェントが操作中", self._chat)
            self._windows.append(win)
            if self._visible:
                win.show_all()
                win._apply_input_region()

    def _request_dismiss(self) -> None:
        """Hide the HUD only; leave the agent running until this session ends."""
        self._dismissed = True
        if self._visible:
            self._hide()

    def _request_stop(self) -> None:
        try:
            subprocess.Popen(
                ["agent-screen-stop"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError:
            self.force_hide()

    def force_hide(self) -> None:
        self._dismissed = True
        self._last_chatgpt = 0.0
        self._last_cursor = 0.0
        if self._visible:
            self._hide()

    def _poll_activity(self) -> Activity | None:
        now = time.time()
        mono = time.monotonic()
        candidates: list[Activity] = []

        if chatgpt_active():
            self._last_chatgpt = mono
            rollout = newest_codex_rollout()
            candidates.append(
                Activity(
                    agent="chatgpt",
                    title="ChatGPTが操作中",
                    chat=extract_chatgpt_chat(rollout),
                    score=self._last_chatgpt,
                )
            )
        elif self._last_chatgpt > 0 and (mono - self._last_chatgpt) < CHAT_HIDE_AFTER_S:
            rollout = newest_codex_rollout()
            candidates.append(
                Activity(
                    agent="chatgpt",
                    title="ChatGPTが操作中",
                    chat=extract_chatgpt_chat(rollout),
                    score=self._last_chatgpt,
                )
            )

        _browser_mtime, transcript = scan_cursor_browser_activity(now)
        if transcript is not None:
            self._last_cursor = mono
            self._cursor_transcript = transcript
            candidates.append(
                Activity(
                    agent="cursor",
                    title="Cursorが操作中",
                    chat=extract_cursor_chat(transcript),
                    score=self._last_cursor,
                )
            )
        elif (
            self._last_cursor > 0
            and (mono - self._last_cursor) < CURSOR_BROWSER_GRACE_S
            and self._cursor_transcript is not None
        ):
            candidates.append(
                Activity(
                    agent="cursor",
                    title="Cursorが操作中",
                    chat=extract_cursor_chat(self._cursor_transcript),
                    score=self._last_cursor,
                )
            )

        if not candidates:
            return None
        return max(candidates, key=lambda a: a.score)

    def _tick(self) -> bool:
        if hide_request_path().exists():
            try:
                hide_request_path().unlink()
            except OSError:
                pass
            self.force_hide()
            return True

        activity = self._poll_activity()
        want = activity is not None
        if not want:
            # Next screen-control session may show the HUD again.
            self._dismissed = False
            if self._visible:
                self._hide()
            return True

        assert activity is not None
        self._agent = activity.agent
        self._title = activity.title
        self._chat = activity.chat
        if self._dismissed:
            return True
        for win in self._windows:
            win.set_content(self._title, self._chat)
        if not self._visible:
            self._show()
        else:
            self._write_active()
        return True

    def _write_active(self) -> None:
        path = active_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "agent": self._agent,
            "pid": os.getpid(),
            "started": self._started or time.time(),
            "title": self._title,
        }
        try:
            path.write_text(json.dumps(payload), encoding="utf-8")
        except OSError:
            pass

    def _clear_active(self) -> None:
        try:
            active_path().unlink(missing_ok=True)
        except OSError:
            pass

    def _show(self) -> None:
        self._visible = True
        self._started = time.time()
        self._write_active()
        swaymsg("mode", "agent-screen")
        for win in self._windows:
            win.set_content(self._title, self._chat)
            win.show_all()
            win._apply_input_region()
            win.queue_draw()

    def _hide(self) -> None:
        self._visible = False
        self._agent = ""
        self._clear_active()
        swaymsg("mode", "default")
        for win in self._windows:
            win.hide()


def main() -> int:
    os.environ.setdefault("GDK_BACKEND", "wayland")
    Gtk.init(sys.argv)
    app = IndicatorApp()

    def _quit(*_args) -> None:
        app.force_hide()
        Gtk.main_quit()

    def _usr1(*_args) -> None:
        GLib.idle_add(app.force_hide)

    signal.signal(signal.SIGTERM, _quit)
    signal.signal(signal.SIGINT, _quit)
    signal.signal(signal.SIGUSR1, _usr1)
    Gtk.main()
    del app
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
