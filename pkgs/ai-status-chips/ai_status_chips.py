#!/usr/bin/env python3
"""Left-edge AI status chips for Sway/Waybar.

Hover near the left waybar AI column → modern chips slide in from the left
(vertically centered, one chip per agent, same order as the bar icons).
Click a chip to expand details; click again or press Esc to collapse / hide.

A trailing control chip toggles the Windows Me startup cue played when all
agents leave the working state (prefs in ~/.config/ai-status/prefs.json).
"""

from __future__ import annotations

import json
import math
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")

from gi.repository import GLib, Gdk, Gtk, GtkLayerShell  # noqa: E402

# Match waybar / Sway chrome.
BG = (0.043, 0.059, 0.078, 0.94)  # #0b0f14
BG_CHIP = (0.082, 0.118, 0.145, 0.96)
BG_CHIP_HOT = (0.082, 0.220, 0.227, 0.98)  # #15383a-ish
ACCENT = (0x33 / 255.0, 0xC5 / 255.0, 0xC5 / 255.0, 1.0)
TEXT = (0.624, 0.906, 0.906, 1.0)  # #9fe7e7
TEXT_DIM = (0.420, 0.467, 0.522, 1.0)  # #6b7785
TEXT_BRIGHT = (0.902, 0.929, 0.953, 1.0)  # #e6edf3
WARN = (0.898, 0.753, 0.482, 1.0)
CRIT = (0.878, 0.424, 0.459, 1.0)

WAYBAR_W = 34
HOVER_EXTRA = 18  # invisible hover pad to the right of the bar
CHIP_W = 268
CHIP_H = 44
CHIP_H_EXPANDED = 148
CHIP_GAP = 10
CHIP_RADIUS = 12
PAD = 14
SLIDE_MS = 220
POLL_MS = 1500
HIDE_GRACE_MS = 280
ANIM_HZ = 60
SOUND_CHIP_KEY = "__sound__"


def runtime_dir() -> Path:
    env = os.environ.get("XDG_RUNTIME_DIR")
    if env:
        return Path(env)
    return Path(f"/run/user/{os.getuid()}")


def config_dir() -> Path:
    env = os.environ.get("XDG_CONFIG_HOME")
    if env:
        return Path(env) / "ai-status"
    return Path.home() / ".config" / "ai-status"


def prefs_path() -> Path:
    return config_dir() / "prefs.json"


def agents_path() -> Path:
    return runtime_dir() / "ai-status-agents.json"


def load_status() -> dict:
    path = agents_path()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def load_agents() -> list[dict]:
    agents = load_status().get("agents")
    return agents if isinstance(agents, list) else []


def load_prefs() -> dict:
    try:
        data = json.loads(prefs_path().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def save_prefs(prefs: dict) -> None:
    path = prefs_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(prefs, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(path)
    except OSError:
        pass


def done_sound_enabled() -> bool:
    """Default on; only an explicit false disables."""
    return load_prefs().get("done_sound", True) is not False


def set_done_sound_enabled(enabled: bool) -> None:
    prefs = load_prefs()
    prefs["done_sound"] = bool(enabled)
    save_prefs(prefs)


def done_sound_path() -> Path | None:
    env = os.environ.get("AI_STATUS_DONE_SOUND")
    if not env:
        return None
    p = Path(env)
    return p if p.is_file() else None


def play_done_sound() -> None:
    wav = done_sound_path()
    if wav is None:
        return
    try:
        subprocess.Popen(
            ["paplay", str(wav)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


def status_color(agent: dict) -> tuple[float, float, float, float]:
    if agent.get("working"):
        return ACCENT
    pct = agent.get("usage_pct")
    if isinstance(pct, (int, float)):
        if pct >= 95:
            return CRIT
        if pct >= 80:
            return WARN
    if agent.get("running"):
        return ACCENT
    return TEXT_DIM


def clamp01(x: float) -> float:
    return 0.0 if x < 0 else 1.0 if x > 1 else x


def ease_out_cubic(t: float) -> float:
    t = clamp01(t)
    return 1.0 - (1.0 - t) ** 3


class ChipsWindow(Gtk.Window):
    def __init__(self, monitor: Gdk.Monitor) -> None:
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self._monitor = monitor
        geo = monitor.get_geometry()
        self._screen_h = geo.height
        self._screen_w = geo.width

        self._agents: list[dict] = []
        self._sound_enabled = done_sound_enabled()
        self._expanded: str | None = None
        self._visible_progress = 0.0  # 0 hidden → 1 shown
        self._want_visible = False
        self._animating = False
        self._pointer_inside = False
        self._hide_source = 0
        self._chip_rects: list[tuple[str, float, float, float, float]] = []

        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_accept_focus(True)
        self.set_can_focus(True)

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "ai-status-chips")
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        GtkLayerShell.set_exclusive_zone(self, 0)
        GtkLayerShell.set_monitor(self, monitor)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, 0)

        self._win_w = WAYBAR_W + HOVER_EXTRA
        self.set_size_request(self._win_w, self._screen_h)

        self.connect("draw", self._on_draw)
        self.connect("enter-notify-event", self._on_enter)
        self.connect("leave-notify-event", self._on_leave)
        self.connect("motion-notify-event", self._on_motion)
        self.connect("button-press-event", self._on_button)
        self.connect("key-press-event", self._on_key)
        self.connect("realize", lambda *_: self._apply_input_region())
        self.add_events(
            Gdk.EventMask.ENTER_NOTIFY_MASK
            | Gdk.EventMask.LEAVE_NOTIFY_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK
            | Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.KEY_PRESS_MASK
        )

        self.show_all()
        self._apply_input_region()

    def set_agents(self, agents: list[dict]) -> None:
        sound = done_sound_enabled()
        if agents == self._agents and sound == self._sound_enabled:
            return
        self._agents = agents
        self._sound_enabled = sound
        if self._expanded and not any(a.get("key") == self._expanded for a in agents):
            self._expanded = None
        self._layout_dirty()
        self.queue_draw()

    def toggle_done_sound(self) -> None:
        enabled = not self._sound_enabled
        set_done_sound_enabled(enabled)
        self._sound_enabled = enabled
        if enabled:
            play_done_sound()
        self.queue_draw()

    def _layout_dirty(self) -> None:
        target_w = (
            WAYBAR_W + HOVER_EXTRA + int(CHIP_W * self._visible_progress) + PAD
            if self._visible_progress > 0.01
            else WAYBAR_W + HOVER_EXTRA
        )
        if target_w != self._win_w:
            self._win_w = target_w
            self.set_size_request(self._win_w, self._screen_h)
            self.resize(self._win_w, self._screen_h)
            self._apply_input_region()

    def _chip_entries(self) -> list[tuple[str, int]]:
        """(key, height) for agent chips plus the done-sound toggle."""
        entries: list[tuple[str, int]] = []
        for a in self._agents:
            key = str(a.get("key") or "")
            h = CHIP_H_EXPANDED if key == self._expanded else CHIP_H
            entries.append((key, h))
        # Always show the sound control when any agent status is available,
        # and also alone so the toggle stays reachable.
        entries.append((SOUND_CHIP_KEY, CHIP_H))
        return entries

    def _stack_geometry(self) -> tuple[float, list[tuple[str, float, float, float, float]]]:
        """Return (slide_x, [(key,x,y,w,h), ...]) with vertical centering."""
        entries = self._chip_entries()
        n = len(entries)
        if n == 0:
            return 0.0, []
        total_h = sum(h for _, h in entries) + CHIP_GAP * (n - 1)
        y0 = (self._screen_h - total_h) / 2.0
        # Slide: off under the bar → parked to the right of the bar.
        hidden_x = float(WAYBAR_W - CHIP_W - 8)
        shown_x = float(WAYBAR_W + 10)
        t = ease_out_cubic(self._visible_progress)
        slide_x = hidden_x + (shown_x - hidden_x) * t
        rects: list[tuple[str, float, float, float, float]] = []
        y = y0
        for key, h in entries:
            rects.append((key, slide_x, y, float(CHIP_W), float(h)))
            y += h + CHIP_GAP
        return slide_x, rects

    def _hover_band(self) -> tuple[int, int, int, int]:
        """Input hit region while collapsed: center band covering AI icons."""
        # Waybar modules-center sits mid-bar; cover ~middle 55% of the screen.
        band_h = int(self._screen_h * 0.55)
        y = (self._screen_h - band_h) // 2
        return (0, y, WAYBAR_W + HOVER_EXTRA, band_h)

    def _apply_input_region(self) -> None:
        window = self.get_window()
        if window is None:
            return
        region = cairo.Region()
        if self._visible_progress > 0.05 or self._want_visible:
            # Full chip column + hover pad.
            rect = cairo.RectangleInt(0, 0, max(self._win_w, WAYBAR_W + HOVER_EXTRA + CHIP_W), self._screen_h)
            region = cairo.Region(rect)
        else:
            x, y, w, h = self._hover_band()
            region = cairo.Region(cairo.RectangleInt(x, y, w, h))
        window.input_shape_combine_region(region, 0, 0)

    def _request_show(self) -> None:
        self._cancel_hide()
        self._want_visible = True
        try:
            self.present()
        except Exception:
            pass
        self._start_anim()

    def _request_hide(self, *, force: bool = False) -> None:
        if self._expanded and not force:
            return
        self._want_visible = False
        self._expanded = None
        self._start_anim()

    def _cancel_hide(self) -> None:
        if self._hide_source:
            GLib.source_remove(self._hide_source)
            self._hide_source = 0

    def _schedule_hide(self) -> None:
        self._cancel_hide()

        def _go() -> bool:
            self._hide_source = 0
            if not self._pointer_inside:
                self._request_hide()
            return False

        self._hide_source = GLib.timeout_add(HIDE_GRACE_MS, _go)

    def _start_anim(self) -> None:
        if self._animating:
            return
        self._animating = True
        self._anim_last = time.monotonic()
        GLib.timeout_add(int(1000 / ANIM_HZ), self._anim_tick)

    def _anim_tick(self) -> bool:
        now = time.monotonic()
        dt = now - getattr(self, "_anim_last", now)
        self._anim_last = now
        speed = 1.0 / (SLIDE_MS / 1000.0)
        target = 1.0 if self._want_visible else 0.0
        if self._visible_progress < target:
            self._visible_progress = min(target, self._visible_progress + dt * speed)
        elif self._visible_progress > target:
            self._visible_progress = max(target, self._visible_progress - dt * speed)
        self._layout_dirty()
        self.queue_draw()
        if abs(self._visible_progress - target) < 0.001:
            self._visible_progress = target
            self._animating = False
            self._apply_input_region()
            return False
        return True

    def _on_enter(self, _w, event) -> bool:
        if event.detail == Gdk.NotifyType.INFERIOR:
            return False
        self._pointer_inside = True
        self._request_show()
        return False

    def _on_leave(self, _w, event) -> bool:
        if event.detail == Gdk.NotifyType.INFERIOR:
            return False
        self._pointer_inside = False
        self._schedule_hide()
        return False

    def _on_motion(self, _w, event) -> bool:
        self._pointer_inside = True
        self._cancel_hide()
        if not self._want_visible and event.x <= WAYBAR_W + HOVER_EXTRA:
            self._request_show()
        return False

    def _hit_chip(self, x: float, y: float) -> str | None:
        for key, cx, cy, cw, ch in self._chip_rects:
            if cx <= x <= cx + cw and cy <= y <= cy + ch:
                return key
        return None

    def _on_button(self, _w, event) -> bool:
        if event.button != 1:
            return False
        if self._visible_progress < 0.5:
            self._request_show()
            return True
        key = self._hit_chip(event.x, event.y)
        if key is None:
            if self._expanded:
                self._expanded = None
                self.queue_draw()
            else:
                self._request_hide(force=True)
            return True
        if key == SOUND_CHIP_KEY:
            self.toggle_done_sound()
            return True
        if self._expanded == key:
            self._expanded = None
        else:
            self._expanded = key
        self._layout_dirty()
        self.queue_draw()
        return True

    def _on_key(self, _w, event) -> bool:
        keyval = event.keyval
        if keyval == Gdk.KEY_Escape:
            if self._expanded:
                self._expanded = None
                self.queue_draw()
            else:
                self._request_hide(force=True)
            return True
        return False

    def _rounded_rect(
        self, cr: cairo.Context, x: float, y: float, w: float, h: float, r: float
    ) -> None:
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    def _draw_text(
        self,
        cr: cairo.Context,
        text: str,
        x: float,
        y: float,
        *,
        size: float = 13,
        bold: bool = False,
        color=TEXT,
        max_w: float | None = None,
    ) -> float:
        cr.select_font_face(
            "Sans",
            cairo.FONT_SLANT_NORMAL,
            cairo.FONT_WEIGHT_BOLD if bold else cairo.FONT_WEIGHT_NORMAL,
        )
        cr.set_font_size(size)
        shown = text
        if max_w is not None:
            while shown and cr.text_extents(shown).width > max_w:
                shown = shown[:-1]
            if shown != text and shown:
                shown = shown[:-1] + "…"
        cr.set_source_rgba(*color)
        ext = cr.text_extents(shown)
        cr.move_to(x, y + ext.height)
        cr.show_text(shown)
        return ext.height

    def _draw_chip(
        self, cr: cairo.Context, agent: dict, x: float, y: float, w: float, h: float
    ) -> None:
        key = str(agent.get("key") or "")
        expanded = key == self._expanded
        hot = agent.get("working") or expanded
        bg = BG_CHIP_HOT if hot else BG_CHIP
        accent = status_color(agent)

        # Soft shadow
        cr.set_source_rgba(0, 0, 0, 0.28 * self._visible_progress)
        self._rounded_rect(cr, x + 2, y + 3, w, h, CHIP_RADIUS)
        cr.fill()

        cr.set_source_rgba(*bg)
        self._rounded_rect(cr, x, y, w, h, CHIP_RADIUS)
        cr.fill()
        cr.set_source_rgba(*accent)
        cr.set_line_width(1.6 if hot else 1.1)
        self._rounded_rect(cr, x, y, w, h, CHIP_RADIUS)
        cr.stroke()

        # Left accent bar
        cr.set_source_rgba(*accent)
        self._rounded_rect(cr, x, y + 6, 3, h - 12, 1.5)
        cr.fill()

        icon = str(agent.get("icon") or "?")
        mark = str(agent.get("status_mark") or "·")
        label = str(agent.get("label") or key)
        pct = agent.get("usage_pct")
        pct_s = ""
        if isinstance(pct, (int, float)):
            pct_s = f"{int(round(pct))}%"

        # Nerd Font for bar-matching glyphs; Sans for CJK labels.
        cr.select_font_face(
            "JetBrainsMono Nerd Font",
            cairo.FONT_SLANT_NORMAL,
            cairo.FONT_WEIGHT_NORMAL,
        )
        cr.set_font_size(16)
        cr.set_source_rgba(*accent)
        cr.move_to(x + 14, y + 28)
        cr.show_text(icon)
        self._draw_text(
            cr, label, x + 40, y + 8, size=13, bold=True, color=TEXT_BRIGHT, max_w=140
        )
        status_label = (
            "作業中" if agent.get("working") else "起動中" if agent.get("running") else "待機"
        )
        self._draw_text(
            cr,
            f"{mark} {status_label}",
            x + 40,
            y + 26,
            size=11,
            color=accent if agent.get("working") or agent.get("running") else TEXT_DIM,
            max_w=150,
        )
        if pct_s:
            cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
            cr.set_font_size(12)
            tw = cr.text_extents(pct_s).width
            self._draw_text(
                cr, pct_s, x + w - PAD - tw, y + 14, size=12, bold=True, color=accent
            )

        if expanded:
            detail_y = y + 48
            work = str(agent.get("work") or "").strip()
            usage = str(agent.get("usage_line") or "").strip()
            extras = [str(e) for e in (agent.get("extras") or []) if str(e).strip()]
            lines: list[tuple[str, tuple]] = []
            if work:
                lines.append((work, TEXT))
            if usage:
                lines.append((f"使用量 {usage}", TEXT_DIM))
            for e in extras[:4]:
                lines.append((e, TEXT_DIM))
            if not lines:
                lines.append(("詳細なし — クリックで閉じる", TEXT_DIM))
            else:
                lines.append(("クリックで閉じる · Esc", TEXT_DIM))
            cy = detail_y
            for text, color in lines:
                self._draw_text(cr, text, x + 14, cy, size=11, color=color, max_w=w - 28)
                cy += 16
                if cy > y + h - 10:
                    break

    def _draw_sound_chip(
        self, cr: cairo.Context, x: float, y: float, w: float, h: float
    ) -> None:
        on = self._sound_enabled
        bg = BG_CHIP_HOT if on else BG_CHIP
        accent = ACCENT if on else TEXT_DIM

        cr.set_source_rgba(0, 0, 0, 0.28 * self._visible_progress)
        self._rounded_rect(cr, x + 2, y + 3, w, h, CHIP_RADIUS)
        cr.fill()

        cr.set_source_rgba(*bg)
        self._rounded_rect(cr, x, y, w, h, CHIP_RADIUS)
        cr.fill()
        cr.set_source_rgba(*accent)
        cr.set_line_width(1.6 if on else 1.1)
        self._rounded_rect(cr, x, y, w, h, CHIP_RADIUS)
        cr.stroke()

        cr.set_source_rgba(*accent)
        self._rounded_rect(cr, x, y + 6, 3, h - 12, 1.5)
        cr.fill()

        # Speaker glyph (Nerd Font / Font Awesome).
        icon = "\uf028" if on else "\uf026"
        cr.select_font_face(
            "JetBrainsMono Nerd Font",
            cairo.FONT_SLANT_NORMAL,
            cairo.FONT_WEIGHT_NORMAL,
        )
        cr.set_font_size(16)
        cr.set_source_rgba(*accent)
        cr.move_to(x + 14, y + 28)
        cr.show_text(icon)

        self._draw_text(
            cr,
            "完了音",
            x + 40,
            y + 8,
            size=13,
            bold=True,
            color=TEXT_BRIGHT,
            max_w=140,
        )
        state = "ON（Windows Me）" if on else "OFF"
        self._draw_text(
            cr,
            state,
            x + 40,
            y + 26,
            size=11,
            color=accent,
            max_w=180,
        )
        tip = "クリックで切替"
        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        cr.set_font_size(10)
        tw = cr.text_extents(tip).width
        self._draw_text(cr, tip, x + w - PAD - tw, y + 16, size=10, color=TEXT_DIM)

    def _on_draw(self, _widget, cr: cairo.Context) -> bool:
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        if self._visible_progress < 0.01:
            self._chip_rects = []
            return False

        alpha = clamp01(self._visible_progress)
        cr.push_group()
        _, rects = self._stack_geometry()
        self._chip_rects = rects
        by_key = {str(a.get("key") or ""): a for a in self._agents}
        for key, x, y, w, h in rects:
            if key == SOUND_CHIP_KEY:
                self._draw_sound_chip(cr, x, y, w, h)
                continue
            agent = by_key.get(key)
            if agent is not None:
                self._draw_chip(cr, agent, x, y, w, h)
        cr.pop_group_to_source()
        cr.paint_with_alpha(alpha)
        return False


class App:
    def __init__(self) -> None:
        self._display = Gdk.Display.get_default()
        if self._display is None:
            raise SystemExit("no Gdk display (need a Wayland session)")
        self._windows: list[ChipsWindow] = []
        # None until first poll; avoid playing on service start.
        self._was_working: bool | None = None
        self._rebuild()
        if hasattr(self._display, "connect"):
            try:
                self._display.connect("monitor-added", lambda *_: self._rebuild())
                self._display.connect("monitor-removed", lambda *_: self._rebuild())
            except TypeError:
                pass
        GLib.timeout_add(POLL_MS, self._poll)

    def _rebuild(self) -> None:
        for w in self._windows:
            w.destroy()
        self._windows = []
        n = self._display.get_n_monitors()
        for i in range(n):
            mon = self._display.get_monitor(i)
            if mon is None:
                continue
            win = ChipsWindow(mon)
            win.set_agents(load_agents())
            self._windows.append(win)

    def _maybe_play_on_idle(self, any_working: bool) -> None:
        if self._was_working is True and not any_working and done_sound_enabled():
            play_done_sound()
        self._was_working = bool(any_working)

    def _poll(self) -> bool:
        status = load_status()
        agents = status.get("agents") if isinstance(status.get("agents"), list) else []
        any_working = bool(status.get("any_working")) or any(
            isinstance(a, dict) and a.get("working") for a in agents
        )
        self._maybe_play_on_idle(any_working)
        for w in self._windows:
            w.set_agents(agents)
        return True


def main() -> int:
    os.environ.setdefault("GDK_BACKEND", "wayland")
    Gtk.init(sys.argv)
    app = App()

    def _quit(*_args) -> None:
        Gtk.main_quit()

    signal.signal(signal.SIGTERM, _quit)
    signal.signal(signal.SIGINT, _quit)
    Gtk.main()
    del app
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
