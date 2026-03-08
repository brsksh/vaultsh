"""Terminal UI: colors, box header, panels, sections, info/warn/error, pause/confirm/prompt, menu."""
from __future__ import annotations

import os
import sys
from typing import Optional
from rich.console import Console
from rich.style import Style
from rich.text import Text
from rich.theme import Theme

# Theme aligned with bash (COLOR_PANEL, BORDER, PRIMARY, ACCENT, SUCCESS, WARN, ERROR, MUTED)
VAULTSH_THEME = Theme({
    "panel": Style(color="grey30"),
    "border": Style(color="grey27"),
    "primary": Style(color="rgb(223,175,143)"),
    "accent": Style(color="rgb(205,100,65)"),   # stronger terracotta so shortcuts stand out
    "success": Style(color="rgb(151,205,151)"),
    "warn": Style(color="rgb(222,184,135)"),
    "error": Style(color="rgb(210,120,120)"),
    "muted": Style(color="grey63"),
    "separator": Style(color="grey50", dim=True),  # for · in header line2
    "secondary": Style(color="rgb(180,160,120)"),
    "bold": Style(bold=True),
    "dim": Style(dim=True),
})

HEADER_WIDTH = 72
_console: Optional[Console] = None


def _no_color() -> bool:
    return os.environ.get("NO_COLOR", "").strip() != "" or not sys.stdout.isatty()


def console() -> Console:
    global _console
    if _console is None:
        force_terminal = None if _no_color() else True
        _console = Console(theme=VAULTSH_THEME, force_terminal=force_terminal)
    return _console


def clear_screen() -> None:
    if sys.stdout.isatty():
        console().clear()


def reset_terminal() -> None:
    """Restore terminal state on exit so the shell prompt appears correctly (no hang, no raw ANSI)."""
    if not sys.stdout.isatty():
        return
    try:
        # Exit alternate screen, reset SGR, show cursor
        out = sys.stdout
        out.write("\033[?1049l\033[0m\033[?25h\n")
        out.flush()
        if sys.stderr is not out:
            sys.stderr.flush()
    except Exception:
        pass


def _rule(char: str = "─", width: int = HEADER_WIDTH) -> str:
    return char * min(width, max(0, width))


def _pad(s: str, width: int) -> str:
    visible = len(s)
    return s + " " * max(0, width - visible)


def _box_line(inner: str, width: int = HEADER_WIDTH) -> str:
    """Pad inner to width chars so that │ + inner + │ has total width width + 2."""
    return (inner + " " * width)[:width]


def _shorten_addr(addr: str, max_len: int = 32) -> str:
    """Display-friendly address: strip scheme, optional path, truncate."""
    s = (addr or "").strip()
    if "://" in s:
        s = s.split("://", 1)[1]
    if "/" in s and not s.startswith("/"):
        s = s.split("/", 1)[0]
    s = s.rstrip("/")
    return (s[: max_len - 1] + "…") if len(s) > max_len else s


def print_header(
    session_line: Optional[str],
    session_color: str,
    token_badge: str,
    token_color: str,
    menu_badge: str,
    nav_root: str,
    address: str,
    show_hint_panels: bool = True,
) -> None:
    """Compact header: one box (Vault + session, addr, nav), optional one-line hint. Panels only when show_hint_panels."""
    c = console()
    w = HEADER_WIDTH
    top = _rule("─", w)
    # One compact box: line1 = Vault + session, line2 = addr | nav | token
    session_part = f"  ● {session_line}" if session_line else "  ● —"
    prefix = " HashiCorp Vault"
    pad = max(0, w - len(prefix) - len(session_part))
    c.print(Text("╭" + top + "╮", style="border"))
    c.print(Text("│", style="border") + Text(prefix, style="bold primary") + Text(session_part + " " * pad, style=session_color) + Text("│", style="border"))
    addr_short = _shorten_addr(address)
    sep = "  ·  "
    line2_raw = f" {addr_short}{sep}nav: {nav_root}{sep}{token_badge} {menu_badge}"
    line2_padded = (line2_raw + " " * w)[:w]
    line2_text = Text("│", style="border")
    for i, part in enumerate(line2_padded.split(sep)):
        if i > 0:
            line2_text.append(sep, style="separator")
        line2_text.append(part, style="dim")
    line2_text.append("│", style="border")
    c.print(line2_text)
    c.print(Text("╰" + top + "╯", style="border"))
    if show_hint_panels:
        c.print(Text("  Login first; then browse or read. Optional: VAULTSH_NAV_ROOT=kv/ to skip mount list.", style="muted"))
    c.print()


def print_panel(title: str, *lines: str) -> None:
    """Draw a box with title in the top border; top/bottom borders match (ASCII-only for alignment)."""
    c = console()
    inner = HEADER_WIDTH  # 72 chars between corners → total line length 74
    title_part = f" [{title}] "  # ASCII only so box aligns in all terminals
    if len(title_part) > inner:
        title_part = title_part[: inner - 2] + ".. "
    top_inner = (title_part + "─" * inner)[:inner]
    c.print()
    c.print(Text("╭" + top_inner + "╮", style="border"))
    c.print(Text("│" + "─" * inner + "│", style="border"))
    for line in lines:
        content = ("   " + line)[:inner].ljust(inner)
        c.print(Text("│", style="border") + Text(content, style="panel") + Text("│", style="border"))
    c.print(Text("╰" + "─" * inner + "╯", style="border"))
    c.print()


def print_section(label: str, title: Optional[str] = None) -> None:
    c = console()
    t = title or label
    c.print()
    c.print(Text(f"[{label}] ", style="accent primary") + Text(t, style="bold"))


def info(msg: str) -> None:
    console().print(Text("INFO ", style="primary") + Text(msg))


def warn(msg: str) -> None:
    _stderr_console().print(Text("WARN ", style="warn") + Text(msg))


def _stderr_console() -> Console:
    return Console(theme=VAULTSH_THEME, file=sys.stderr, force_terminal=None if _no_color() else True)


def error(msg: str) -> None:
    _stderr_console().print(Text("ERROR ", style="error") + Text(msg))


def show_guidance(title: str, line_one: str, line_two: str = "") -> None:
    c = console()
    c.print(Text(f"[{title}]", style="panel bold"))
    c.print(Text(f"  {line_one}", style="muted"))
    if line_two:
        c.print(Text(f"  {line_two}", style="muted"))
    c.print(Text(_rule("─", HEADER_WIDTH), style="panel"))
    c.print()


def pause() -> None:
    console().print()
    try:
        console().print(Text("Press Enter to continue...", style="muted"), end="")
        input()
    except (EOFError, KeyboardInterrupt):
        pass


def confirm(prompt_text: str, default_no: bool = True) -> bool:
    suffix = " [y/N]: " if default_no else " [Y/n]: "
    try:
        reply = input(prompt_text + suffix).strip().lower()
    except (EOFError, KeyboardInterrupt):
        return False
    if default_no:
        return reply in ("y", "yes")
    return reply not in ("n", "no")


def prompt(text: str, default: str = "") -> str:
    if default:
        try:
            reply = input(f"{text} [{default}]: ").strip()
        except (EOFError, KeyboardInterrupt):
            return default
        return reply if reply else default
    try:
        return input(f"{text}: ").strip()
    except (EOFError, KeyboardInterrupt):
        return ""


def prompt_secret(text: str) -> str:
    try:
        import getpass
        return getpass.getpass(f"{text}: ")
    except (EOFError, KeyboardInterrupt):
        return ""


def print_preview(label: str, *parts: str) -> None:
    console().print()
    console().print(Text(f"[preview] ", style="panel accent") + Text(label, style="primary"))
    console().print("  " + " ".join(repr(p) for p in parts))
    console().print(Text(_rule("─", HEADER_WIDTH), style="panel"))


def _use_interactive_menu() -> bool:
    """True if we can use questionary (TTY, no NO_COLOR forcing raw)."""
    return sys.stdin.isatty() and sys.stdout.isatty()


# Quick actions hint for questionary (ESC = back, ↑↓ = move, etc.)
_MENU_INSTRUCTION = "↑↓ move  ·  Enter select  ·  ESC back  ·  1-9 / letter shortcut"


def _add_esc_back_binding(application):
    """Add ESC → cancel to the prompt_toolkit Application so .ask() returns None on ESC."""
    try:
        from prompt_toolkit.keys import Keys
        kb = application.key_bindings

        @kb.add(Keys.Escape, eager=True)
        def _(_event):
            _event.app.exit(exception=KeyboardInterrupt)
    except Exception:
        pass


def _questionary_style():
    """questionary Style matching vaultsh theme (warm primary/accent)."""
    try:
        from prompt_toolkit.styles import Style as PtStyle
        return PtStyle.from_dict({
            "pointer": "#cd6441 bold",       # accent (matches VAULTSH_THEME accent)
            "highlighted": "#cd6441",
            "selected": "#dfaf8f bold",       # primary
            "question": "bold",
            "instruction": "italic dim #6b6b6b",
            "qmark": "#cd6441 bold",
        })
    except Exception:
        return None


def select_option(
    prompt_text: str,
    options: list[tuple[str, str, str]],
    fzf_header_extra: str = "",
) -> Optional[str]:
    """Options: (key, label, description). Returns key or None on cancel."""
    if not options:
        return None
    if _use_interactive_menu():
        try:
            import questionary
            choices = [
                questionary.Choice(title=f"  {key}  {label}", value=key)
                for key, label, _ in options
            ]
            style = _questionary_style()
            kwargs = {
                "choices": choices,
                "use_shortcuts": True,
                "use_indicator": True,
                "pointer": "▸",
                "instruction": _MENU_INSTRUCTION,
            }
            if style is not None:
                kwargs["style"] = style
            q = questionary.select(prompt_text, **kwargs)
            _add_esc_back_binding(q.application)
            ans = q.ask(kbi_msg="")
            return ans
        except (KeyboardInterrupt, EOFError):
            return None
        except ImportError:
            pass
    # Fallback: numbered list + input
    console().print(Text(prompt_text, style="bold"))
    for i, (key, label, desc) in enumerate(options):
        num = str(i + 1) if i < 9 else ""
        console().print(Text(f"  {num or '·'} ", style="accent") + Text(f"[{key}] ", style="accent") + Text(label, style="primary"))
        if desc:
            console().print(Text(f"      {desc}", style="muted"))
    console().print(Text("  Number or letter, then Enter.", style="muted"))
    try:
        sel = input("Choice: ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        return None
    if not sel:
        return None
    for key, label, _ in options:
        if key.lower() == sel:
            return key
    if sel.isdigit():
        idx = int(sel) - 1
        if 0 <= idx < len(options):
            return options[idx][0]
    return None


def pick_from_list(header: str, options: list[str]) -> Optional[str]:
    """Let user pick one option; return selected string or None."""
    if not options:
        return None
    if _use_interactive_menu():
        try:
            import questionary
            choices = [questionary.Choice(title=opt, value=opt) for opt in options]
            style = _questionary_style()
            kwargs = {
                "choices": choices,
                "use_shortcuts": True,
                "use_indicator": True,
                "pointer": "▸",
                "instruction": _MENU_INSTRUCTION,
            }
            if style is not None:
                kwargs["style"] = style
            q = questionary.select(header, **kwargs)
            _add_esc_back_binding(q.application)
            return q.ask(kbi_msg="")
        except (KeyboardInterrupt, EOFError):
            return None
        except ImportError:
            pass
    console().print(Text(header, style="bold"))
    for i, opt in enumerate(options, 1):
        console().print(Text(f"  [{i}] ", style="accent") + opt)
    console().print()
    try:
        sel = input("Choice (number or Enter to cancel): ").strip()
    except (EOFError, KeyboardInterrupt):
        return None
    if not sel:
        return None
    if sel.isdigit():
        idx = int(sel) - 1
        if 0 <= idx < len(options):
            return options[idx]
    if sel in options:
        return sel
    return None


def print_kv(label: str, value: str, label_width: int = 12) -> None:
    display_label = (label[: label_width - 1] + "…") if len(label) > label_width else label
    console().print(Text(f"{display_label:<{label_width}}", style="muted") + Text(value, style="bold"))
