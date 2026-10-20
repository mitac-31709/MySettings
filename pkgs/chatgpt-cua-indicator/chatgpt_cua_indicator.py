#!/usr/bin/env python3
"""Sway/wlroots overlay while an agent is driving the screen / browser.

ChatGPT Computer Use: sky_linux / active_execs.
Cursor: recent browser_* / cursor-ide-browser tool_use in agent transcripts.

Shows a click-through edge frame, top-center banner, chat panel underneath,
and a Stop button. Esc is handled via Sway mode "agent-screen".
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
STOP_BG = (0.88, 0.27, 0.35, 0.95)  # soft-ish
EDGE_PX = 4
PILL_PAD_X = 18
PILL_PAD_Y = 10
PILL_TOP = 28
PANEL_W = 560
PANEL_H = 220
PANEL_GAP = 10
PANEL_PAD = 12
STOP_W = 72
STOP_H = 28
STOP_MARGIN = 10
HINT = "Escで停止"
# Grace after ChatGPT helper vanishes (covers restarts).
CHAT_HIDE_AFTER_S = 2.0
# Cursor browser tools are bursty; keep HUD up between actions.
CURSOR_BROWSER_GRACE_S = 10.0
POLL_MS = 400
CHAT_MAX_CHARS = 1800
SKY_RE = re.compile(r"sky_linux")
BROWSER_TOOL_RE = re.compile(
    r"(?:browser_[a-z0-9_]+|cursor-ide-browser)", re.IGNORECASE
)


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


def _recent_lines_have_browser_tools(path: Path, last_n: int = 40) -> bool:
    """True only if browser tools appear in the newest transcript lines."""
    text = _read_tail_text(path, max_bytes=96_000)
    if not text:
        return False
    for line in text.splitlines()[-last_n:]:
        if not BROWSER_TOOL_RE.search(line):
            continue
        # Require an actual tool invocation, not a prose mention.
        if '"tool_use"' in line or "CallDynamicTool" in line or '"browser_' in line:
            return True
    return False


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
                try:
                    mtime = jsonl.stat().st_mtime
                except OSError:
                    continue
                # Skip cold files; keep scans cheap.
                if now - mtime > CURSOR_BROWSER_GRACE_S * 3:
                    continue
                if not _recent_lines_have_browser_tools(jsonl):
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
        self._stop_rect = (0.0, 0.0, 0.0, 0.0)  # x,y,w,h
        self._panel_rect = (0.0, 0.0, 0.0, 0.0)
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
            GtkLayerShell.set_margin(self, edge, 0)

        geo = monitor.get_geometry()
        self._width = geo.width
        self._height = geo.height
        self.set_size_request(self._width, self._height)

        self.connect("draw", self._on_draw)
        self.connect("realize", self._on_realize)
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

    def _apply_input_region(self) -> None:
        window = self.get_window()
        if window is None:
            return
        # Click-through everywhere except the Stop button on the primary monitor.
        region = cairo.Region()
        if self._primary:
            x, y, w, h = self._stop_rect
            if w > 0 and h > 0:
                rect = cairo.RectangleInt(int(x), int(y), int(w), int(h))
                region = cairo.Region(rect)
        window.input_shape_combine_region(region, 0, 0)

    def _on_button(self, _widget, event) -> bool:
        if not self._primary or self._on_stop is None:
            return False
        x, y, w, h = self._stop_rect
        if x <= event.x <= x + w and y <= event.y <= y + h:
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

        # Chat panel directly under the banner (primary monitor only).
        if self._primary:
            panel_x = (w - PANEL_W) / 2
            panel_y = pill_y + pill_h + PANEL_GAP
            self._panel_rect = (panel_x, panel_y, PANEL_W, PANEL_H)

            cr.set_source_rgba(*PANEL_BG)
            self._rounded_rect(cr, panel_x, panel_y, PANEL_W, PANEL_H, 8)
            cr.fill()
            cr.set_source_rgba(*ACCENT)
            cr.set_line_width(1.5)
            self._rounded_rect(cr, panel_x, panel_y, PANEL_W, PANEL_H, 8)
            cr.stroke()

            stop_x = panel_x + PANEL_W - STOP_W - STOP_MARGIN
            stop_y = panel_y + PANEL_H - STOP_H - STOP_MARGIN
            self._stop_rect = (stop_x, stop_y, STOP_W, STOP_H)

            chat_bottom = stop_y - 8
            self._draw_wrapped_text(
                cr,
                self._chat or "（思考・操作ログを待機中…）",
                panel_x + PANEL_PAD,
                panel_y + PANEL_PAD,
                PANEL_W - PANEL_PAD * 2,
                chat_bottom - (panel_y + PANEL_PAD),
            )

            cr.set_source_rgba(*STOP_BG)
            self._rounded_rect(cr, stop_x, stop_y, STOP_W, STOP_H, 6)
            cr.fill()
            cr.set_source_rgba(1, 1, 1, 1)
            cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
            cr.set_font_size(13)
            stop_label = "停止"
            se = cr.text_extents(stop_label)
            cr.move_to(
                stop_x + (STOP_W - se.width) / 2,
                stop_y + (STOP_H + se.height) / 2,
            )
            cr.show_text(stop_label)
            self._apply_input_region()
        else:
            self._stop_rect = (0.0, 0.0, 0.0, 0.0)
            self._apply_input_region()

        return False

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
            win._on_stop = self._request_stop
            win.set_content(self._title or "エージェントが操作中", self._chat)
            self._windows.append(win)
            if self._visible:
                win.show_all()
                win._apply_input_region()

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

        browser_mtime, transcript = scan_cursor_browser_activity(now)
        if transcript is not None and (now - browser_mtime) <= CURSOR_BROWSER_GRACE_S:
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
        if want and activity is not None:
            self._agent = activity.agent
            self._title = activity.title
            self._chat = activity.chat
            for win in self._windows:
                win.set_content(self._title, self._chat)
            if not self._visible:
                self._show()
            else:
                self._write_active()
        elif not want and self._visible:
            self._hide()
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
