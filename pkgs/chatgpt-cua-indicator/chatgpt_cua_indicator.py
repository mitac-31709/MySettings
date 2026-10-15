#!/usr/bin/env python3
"""Sway/wlroots overlay: show when ChatGPT Computer Use is driving the desktop.

Watches ~/.codex/node_repl/active_execs and sky_linux CPU activity, then draws a
click-through edge frame + status pill via gtk-layer-shell.
"""

from __future__ import annotations

import os
import re
import signal
import sys
import time
from pathlib import Path

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")

from gi.repository import GLib, Gdk, Gtk, GtkLayerShell  # noqa: E402

ACCENT = (0x33 / 255.0, 0x9C / 255.0, 0xFF / 255.0, 1.0)
PILL_BG = (0.043, 0.059, 0.078, 0.92)  # #0b0f14-ish
EDGE_PX = 4
PILL_PAD_X = 18
PILL_PAD_Y = 10
PILL_TOP = 28
TITLE = "ChatGPTが操作中"
HINT = "Escでキャンセル"
HIDE_AFTER_S = 1.5
POLL_MS = 250
SKY_RE = re.compile(r"sky_linux")


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


def sky_linux_cpu_ticks() -> dict[int, int]:
    """Map pid -> utime+stime for processes whose cmdline mentions sky_linux."""
    out: dict[int, int] = {}
    try:
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            pid = int(entry.name)
            try:
                cmdline = (entry / "cmdline").read_bytes()
            except OSError:
                continue
            text = cmdline.replace(b"\0", b" ").decode("utf-8", "replace")
            if not SKY_RE.search(text):
                continue
            try:
                fields = (entry / "stat").read_text().split()
                # utime=13, stime=14 (1-based field numbers → index 13,14)
                out[pid] = int(fields[13]) + int(fields[14])
            except (OSError, IndexError, ValueError):
                continue
    except OSError:
        pass
    return out


class OverlayWindow(Gtk.Window):
    def __init__(self, monitor: Gdk.Monitor) -> None:
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
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
        GtkLayerShell.set_namespace(self, "chatgpt-cua-indicator")
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

    def _on_realize(self, *_args) -> None:
        self._apply_click_through()

    def _apply_click_through(self) -> None:
        window = self.get_window()
        if window is None:
            return
        # Empty input region: pointer/touch pass through to windows below.
        region = cairo.Region()
        window.input_shape_combine_region(region, 0, 0)

    def _on_draw(self, _widget, cr: cairo.Context) -> bool:
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        w, h = self._width, self._height
        cr.set_source_rgba(*ACCENT)
        # Edge frame
        cr.rectangle(0, 0, w, EDGE_PX)
        cr.rectangle(0, h - EDGE_PX, w, EDGE_PX)
        cr.rectangle(0, 0, EDGE_PX, h)
        cr.rectangle(w - EDGE_PX, 0, EDGE_PX, h)
        cr.fill()

        # Status pill (top center)
        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(14)
        title_ext = cr.text_extents(TITLE)
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
        cr.show_text(TITLE)

        cr.set_source_rgba(*ACCENT)
        cr.set_font_size(12)
        cr.move_to(
            pill_x + (pill_w - hint_ext.width) / 2,
            pill_y + PILL_PAD_Y + title_ext.height + 6 + hint_ext.height,
        )
        cr.show_text(HINT)
        return False

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
        self._last_activity = 0.0
        self._prev_sky_cpu: dict[int, int] = {}
        self._display = Gdk.Display.get_default()
        if self._display is None:
            raise SystemExit("no Gdk display (need a Wayland session)")

        active_execs_dir().mkdir(parents=True, exist_ok=True)
        self._rebuild_windows()
        if hasattr(self._display, "connect"):
            try:
                self._display.connect("monitor-added", lambda *_: self._rebuild_windows())
                self._display.connect("monitor-removed", lambda *_: self._rebuild_windows())
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
            win = OverlayWindow(mon)
            self._windows.append(win)
            if self._visible:
                win.show_all()
                win._apply_click_through()

    def _activity_now(self) -> bool:
        if has_active_execs():
            return True
        cur = sky_linux_cpu_ticks()
        prev = self._prev_sky_cpu
        self._prev_sky_cpu = cur
        if not cur:
            return False
        if not prev:
            # First sighting of sky_linux: treat as activity once.
            return True
        for pid, ticks in cur.items():
            if pid not in prev or ticks > prev[pid]:
                return True
        return False

    def _tick(self) -> bool:
        now = time.monotonic()
        if self._activity_now():
            self._last_activity = now
        want = self._last_activity > 0 and (now - self._last_activity) < HIDE_AFTER_S
        if want and not self._visible:
            self._show()
        elif not want and self._visible:
            self._hide()
        return True

    def _show(self) -> None:
        self._visible = True
        for win in self._windows:
            win.show_all()
            win._apply_click_through()
            win.queue_draw()

    def _hide(self) -> None:
        self._visible = False
        for win in self._windows:
            win.hide()


def main() -> int:
    # Ensure Wayland for layer-shell.
    os.environ.setdefault("GDK_BACKEND", "wayland")
    Gtk.init(sys.argv)
    app = IndicatorApp()

    def _quit(*_args) -> None:
        Gtk.main_quit()

    signal.signal(signal.SIGTERM, _quit)
    signal.signal(signal.SIGINT, _quit)
    Gtk.main()
    del app
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
