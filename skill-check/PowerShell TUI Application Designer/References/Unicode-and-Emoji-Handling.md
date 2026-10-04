# Unicode and Emoji Handling

Use in SKILL.md phase 6 (Theme) and phase 8 (testing). Icons are CHARACTERS drawn by the terminal's font, not assets. Whether they show depends on the console host, the font and the output encoding - so the app decides once, from facts, and always has a fallback.

## 1. The three tiers

| Tier | When | Glyphs | Width |
|---|---|---|---|
| **Emoji** | Windows Terminal, VS Code terminal, ConEmu, UTF-8 Linux/macOS terminals | colorful emoji (code points >= U+1F300, and U+2705, U+274C) | 2 columns |
| **Symbol** | classic Windows console (conhost, the Windows PowerShell window) | single-column glyphs from the **Windows Glyph List 4 (WGL4)** that every console font draws: `U+25BA ► U+25C4 ◄ U+25B2 ▲ U+25BC ▼ U+25CF ● U+25A0 ■ U+263A ☺ U+263C ☼ U+2666 ♦ U+221A √ U+00D7 × U+266A ♪` etc. | 1 column |
| **Ascii** | redirected output, `NO_COLOR`-style plain mode, forced, unknown terminal | `> < + ! x i * # -` | 1 column |

Rules:
1. A new icon needs **all three forms**; a test asserts every icon has Emoji, Symbol and Ascii forms and that the Ascii form is printable ASCII.
2. The Symbol form MUST be WGL4 (check the glyph list); anything else shows as a box in Consolas/Lucida Console.
3. Avoid emoji that need a variation selector (U+FE0F) to render as emoji (for example the gear U+2699 or the warning sign U+26A0): their width differs between terminals. Use unambiguous wide emoji (U+1F527 wrench, U+1F536 orange diamond, U+2705, U+274C).
4. Source files stay ASCII-only: build glyphs with `[char]::ConvertFromUtf32(0x1F680)` or `[string][char]0x25BA`.

## 2. Decision function (pure, unit-tested)

```text
override env ICONS=emoji|symbol|ascii            -> that tier
ASCII=1                                           -> Ascii
output redirected                                 -> Ascii
non-Windows: LANG/LC_ALL contains UTF-8           -> Emoji, else Ascii
Windows: console cannot be set to UTF-8           -> Ascii
Windows: WT_SESSION or TERM_PROGRAM or ConEmuANSI=ON -> Emoji
Windows otherwise (classic console)               -> Symbol
```

The user's saved choice (Settings `icons`) is applied as the override when no environment override exists. Read the facts in ONE function (`Get-IconTier`); the pure `Resolve-IconTier(env, isWin, redirected)` makes the table testable on any OS.

## 3. Output encoding

* Windows: set `[Console]::OutputEncoding = UTF8Encoding($false)` before drawing - **also when output is redirected** (otherwise a parent process that captures the output receives `?` for every glyph; this was a real defect found by CI).
* The `.bat` launcher switches the console to code page 65001 (`chcp 65001`) and restores the previous code page on exit.
* Child processes: set `StandardOutputEncoding`/`StandardErrorEncoding` to UTF-8 when capturing their output.
* Files you write: UTF-8 **without** BOM (readable by both PowerShell editions and by other tools).

## 4. Font and terminal checks (Windows)

* Segoe UI Emoji (`%WINDIR%\Fonts\seguiemj.ttf`) is part of Windows 10/11; detect it, never download or bundle it (it cannot be redistributed). If it is missing, explain that emoji may show as boxes and offer the Symbol tier.
* Windows Terminal sets `WT_SESSION`; many terminals set `TERM_PROGRAM`. The app cannot SEE how a glyph is drawn: give the user a **preview and a choice** ("Do you see colorful icons? 01 Yes / 02 No, use simple symbols") and remember the answer per user. Offer it once, on first start in an unrecognized terminal, plus a Settings entry.
* Never run system-repair commands (`sfc`, `DISM`) as a reaction to a missing font; only suggest them with concrete evidence of OS file corruption.

## 5. Width and alignment

* Do not align columns by character count when mixing tiers; put the icon at a fixed position and let the label follow after two spaces. Descriptions go on their own indented line, so icon width differences never misalign them.
* Box-drawing characters belong to the same tiers (use ASCII `+ - |` in the Ascii tier). Do not rely on them for meaning.

## 6. Tests

* Table test for `Resolve-IconTier` (Windows Terminal, conhost, redirected, Linux UTF-8, Linux C locale, overrides).
* Every icon has three forms; Ascii form is ASCII.
* An integration test starts the app as a child process with the override `ICONS=emoji` and asserts the emoji arrives in the captured (UTF-8) output.
* Rendering in a real Windows Terminal is a MANUAL check; report it UNVERIFIED unless a person did it.
