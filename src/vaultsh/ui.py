"""Terminal UI: colors, box header, panels, sections, info/warn/error, pause/confirm/prompt, menu."""
from __future__ import annotations

import os
import shutil
import subprocess
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
    "accent": Style(color="rgb(215,135,95)"),
    "success": Style(color="rgb(151,205,151)"),
    "warn": Style(color="rgb(222,184,135)"),
    "error": Style(color="rgb(210,120,120)"),
    "muted": Style(color="grey63"),
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


def has_fzf() -> bool:
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        return False
    return shutil.which("fzf") is not None


def clear_screen() -> None:
    if sys.stdout.isatty():
        console().clear()


def _rule(char: str = "─", width: int = HEADER_WIDTH) -> str:
    return char * min(width, max(0, width))


def _pad(s: str, width: int) -> str:
    visible = len(s)
    return s + " " * max(0, width - visible)


def _box_line(inner: str, width: int = HEADER_WIDTH) -> str:
    """Pad inner to width chars so that │ + inner + │ has total width width + 2."""
    return (inner + " " * width)[:width]


def print_header(
    session_line: Optional[str],
    session_color: str,
    token_badge: str,
    token_color: str,
    menu_badge: str,
    nav_root: str,
    address: str,
) -> None:
    c = console()
    w = HEADER_WIDTH
    top = _rule("─", w)
    if session_line:
        line = f" ● {session_line}"
        c.print(Text("╭" + top + "╮", style="border"))
        c.print(Text("│", style="border") + Text(_box_line(line, w), style=session_color) + Text("│", style="border"))
        c.print(Text("╰" + top + "╯", style="border"))
        c.print()
    c.print(Text("╭" + top + "╮", style="border"))
    c.print(Text("│", style="border") + Text(_box_line(" HashiCorp Vault", w), style="bold primary") + Text("│", style="border"))
    # 72 chars between pipes: " " + "context    " (11) + badge + padding
    c.print(Text("│", style="border") + Text(" ", style="border") + Text("context    ", style="dim") + Text(token_badge, style=token_color) + Text(_pad("", w - 11 - len(token_badge)) + "│", style="border"))
    c.print(Text("│", style="border") + Text(" ", style="border") + Text("menu      ", style="dim") + Text(menu_badge, style="secondary") + Text(_pad("", w - 11 - len(menu_badge)) + "│", style="border"))
    c.print(Text("│", style="border") + Text(" ", style="border") + Text("nav root  ", style="dim") + Text(nav_root, style="accent") + Text(_pad("", w - 11 - len(nav_root)) + "│", style="border"))
    c.print(Text("│", style="border") + Text(" ", style="border") + Text("address   ", style="dim") + Text(address, style="bold") + Text(_pad("", w - 11 - len(address)) + "│", style="border"))
    c.print(Text("╰" + top + "╯", style="border"))
    c.print(Text("  Login, browse, read/write KV secrets, inspect session, diagnose.", style="dim"))
    c.print()


def print_panel(title: str, *lines: str) -> None:
    """Draw a box with title in the top border; top/bottom borders match exactly (HEADER_WIDTH inner)."""
    c = console()
    inner = HEADER_WIDTH  # 72 chars between corners → total line length 74
    title_part = f" ▎ [{title}] "
    if len(title_part) > inner:
        title_part = title_part[: inner - 2] + "… "
    top_inner = (title_part + "─" * inner)[:inner]
    c.print(Text("╭" + top_inner + "╮", style="border"))
    for line in lines:
        content = ("   " + line)[:inner].ljust(inner)
        c.print(Text("│", style="border") + Text(content, style="panel") + Text("│", style="border"))
    c.print(Text("╰" + "─" * inner + "╯", style="border"))


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
        input("Press Enter to continue...")
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


def select_option(
    prompt_text: str,
    options: list[tuple[str, str, str]],
    fzf_header_extra: str = "",
) -> Optional[str]:
    """Options: (key, label, description). Returns key or None on cancel."""
    if not options:
        return None
    if has_fzf():
        lines = [f"{key}. {label}\t{desc}" for key, label, desc in options]
        header = fzf_header_extra or "Move with arrows. Enter confirms. ESC goes back."
        try:
            proc = subprocess.run(
                ["fzf", "--prompt", f"vaultsh > {prompt_text}: ", "--height=~100%", "--layout=reverse",
                 "--border", "--no-sort", "--delimiter=\t", "--with-nth=1",
                 "--preview=printf \"%s\\n\" {2}", "--preview-window=down,4,wrap,border-top",
                 "--pointer=>", "--marker=+",
                 "--header", header],
                input="\n".join(lines),
                capture_output=True,
                text=True,
                timeout=300,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        else:
            if proc.returncode == 0 and proc.stdout:
                first = proc.stdout.strip().split("\n")[0]
                key_part = first.split(".", 1)[0].strip()
                for key, label, _ in options:
                    if key == key_part or f"{key}." == key_part:
                        return key
                return key_part
        return None
    # Numbered fallback
    console().print(Text(prompt_text, style="bold"))
    for key, label, desc in options:
        console().print(Text(f"  [{key}] ", style="accent") + Text(label, style="primary"))
        if desc:
            console().print(Text(f"      {desc}", style="muted"))
    console().print(Text("\nChoose one option and press Enter.", style="muted"))
    try:
        sel = input("Selection: ").strip()
    except (EOFError, KeyboardInterrupt):
        return None
    if not sel:
        return None
    for key, label, _ in options:
        if key == sel:
            return key
    if sel.isdigit():
        idx = int(sel) - 1
        if 0 <= idx < len(options):
            return options[idx][0]
    return sel


def pick_from_list(header: str, options: list[str]) -> Optional[str]:
    """Let user pick one option; return selected string or None."""
    if not options:
        return None
    if has_fzf():
        try:
            proc = subprocess.run(
                ["fzf", "--prompt", f"{header}> ", "--height=~50%", "--layout=reverse",
                 "--border", "--no-sort", "--header", header],
                input="\n".join(options),
                capture_output=True,
                text=True,
                timeout=300,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        else:
            if proc.returncode == 0 and proc.stdout:
                return proc.stdout.strip().split("\n")[0]
        return None
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


def print_kv(label: str, value: str) -> None:
    console().print(Text(f"{label:<12}", style="muted") + Text(value, style="bold"))
