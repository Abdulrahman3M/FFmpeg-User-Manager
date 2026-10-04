# TUI Design Rules

Use in SKILL.md phase 5 (design) and phase 6 (build). Every rule has a testable form; the template's tests already cover most of them.

## 1. Option rule (non-negotiable)

Every selectable option on every screen (menus, submenus, wizard questions, confirmations, notices) is shown as

```text
  NN  Icon  Name
      One-line description: what it does, when to use it, what to expect.
```

* `NN` is two digits, zero-padded: `01`...`09`, `10`, `11`...`99`, `100` and beyond (never truncated).
* No letter shortcuts, no `[Y]/[N]`, no `Q to quit`. Exit and Back are numbered options like any other (Exit is the last number on the main menu). `Esc` = Back; `Ctrl+C` = quit.
* Typing digits selects: `05` selects option 5 at once; a prefix of a longer number (`1` in a list of 12) waits for the next digit; `Enter` accepts what was typed or the highlighted item. Arrow keys move the highlight (wrap around).
* A description is MANDATORY for every option. A disabled option stays visible, dimmed, and its description line becomes the reason ("Needs the X filter, which is not in this build.").
* Yes/No questions are menus: `01 Yes, <what happens>` / `02 No, <what happens>`; both answers are described.

## 2. Screen anatomy (top to bottom)

1. **Header** (once per screen): icon + application name + version on the main screen; icon + task title elsewhere.
2. **Context** (optional): one dim line saying what this screen is for; a "Source" panel when the screen refers to a chosen file/object.
3. **Question or list**: the prompt, then its help line (dim), then options. Typed questions add `Example: ...`.
4. **Feedback** (only when needed): a validation/error line directly above the input.
5. **Footer**: key hints `Up/Down Navigate   Enter Select   01-NN Type a number   Esc Back` (keys in the Key role, labels dim).

Clear and redraw the whole screen on every key; never rely on scrollback for state.

## 3. Message semantics (same words, same icons, same roles everywhere)

| Kind | Icon name | Role | Use for | Wording |
|---|---|---|---|---|
| Success | `Success` | Success | an action finished | past tense, say what exists now ("Saved C:\...") |
| Warning | `Warning` | Warning | allowed but risky/slow/large | say the risk and what the app does anyway |
| Error | `Error` | Error | an action failed or input is invalid | what happened + why + what the user can do next |
| Info | `Info` | Info | neutral facts | one or two sentences |

Never show a raw exception to the user; log it (see Error-Handling.md) and show a plain sentence.

## 4. Forms (typed input)

Prompt, help (what it is, allowed range/format), example, then `> ` with the typed text. Validation runs on Enter; the message appears above the input and clears on the next keystroke; the typed text is kept so the user edits instead of retyping. `Esc` cancels. Prefer choices over typing; offer `Custom...` as the LAST option of a list when free values are legitimate, with its own validated prompt and limits stated in the help.

## 5. Confirmations

Ask before: overwriting, deleting, installing/downloading, stopping a running job, leaving unsaved work. Never overwrite silently: collisions always ask (`01 Replace it`, `02 Choose another name`, `03 Cancel`). Say exactly what will change.

## 6. Progress

Long work shows: a bar (`[#####-----] 50%`), percent, elapsed time, current stage name, and how to cancel (`Esc`, then confirm). Redirected output prints one plain line per step (no carriage returns, no escape codes). Finish with a result screen: success/failure, output path, size, and numbered next actions (`01 Open folder`, `02 Run again`, `03 Main menu`).

## 7. Help, settings, about

* **Help**: every question has a help line; there is no separate manual that the screen depends on.
* **Settings** screen: each setting is a numbered choice with a description and shows the current value in the title; changes apply immediately and are remembered; a "Reset to defaults" option exists when there is more than one setting.
* **About**: name, version (from `VERSION`), platform, PowerShell edition, icon tier, data folder path, license line.

## 8. Layout and responsiveness

* Query the size with `Get-TerminalSize` on every redraw (users resize). Normal >= 80 columns, wide >= 120, narrow < 60.
* Narrow: drop description indentation and wrap, never truncate numbers; Short window (< 20 rows): show a window of the list around the selection and a scroll indicator (`more above/below`).
* Never print wider than the window - wrap or shorten with an ellipsis, not by clipping.

## 9. Color

Colors exist only as ROLES in Theme (`Title`, `Heading`, `Normal`, `Dim`, `Selected`, `Number`, `Key`, `Success`, `Warning`, `Error`, `Info`). Screens call `Write-Ui -Role`. Never write `-ForegroundColor` or ANSI codes outside Theme/Renderer. `NO_COLOR` disables color; the UI must stay fully usable without it (state is never conveyed by color alone: the selected row has a `>` marker, errors have an icon and the word).

## 10. Accessibility and copy

* Keyboard only; no mouse dependence; no timing-dependent input; no flashing.
* Consistent order of keys and wording across screens. Plain words: verbs for actions ("Convert", "Save"), no jargon without a one-line explanation.
* Screen-reader friendly output: no box-drawing as the only separator for information, no decorative repetition; icons are additional, never the only carrier of meaning (the label is always present).
* One language per UI (English by default); do not mix.
