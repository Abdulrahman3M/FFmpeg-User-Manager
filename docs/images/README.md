# Screenshots

These images show the **real application**: each one is a frame of the actual terminal output of `Start-FFmpegTUI.ps1` (version in the window title bar / header)
while it processed a real 40-second 720p test video.

How they were captured (honest note): the app was driven through a pseudo-terminal in a **Linux** environment (PowerShell 7.4, FFmpeg 6.1), the ANSI output was
interpreted by a terminal emulator library and drawn with a monospace font in a headless browser. Nothing was mocked up or edited by hand.
Windows Terminal will look very similar but fonts, emoji and window chrome differ slightly. `main-menu-console-safe.png` is the same application started with `FFTUI_ICONS=symbol`,
which is the icon set the classic Windows console selects automatically; it is drawn here with a Linux monospace font, **not** captured from a real Windows console.
The images were recaptured after the numbered-option redesign (version in the header is the content of `VERSION`). Native Windows captures can replace these files at any time
(keep the same file names).

| File | Screen |
|---|---|
| `main-menu.png` | Main menu: every option is `Number Icon Name` with a description under it (emoji icon set) |
| `main-menu-console-safe.png` | The same menu with the symbol icon set that the classic Windows console uses (single-column glyphs that every console font draws) |
| `ffmpeg-status.png` | FFmpeg Status / Settings (detected tools, capabilities, update status, numbered actions) |
| `conversion-wizard.png` | A wizard question (Convert Video Format, output format) with the *Source* panel, numbered options and a description under each |
| `video-to-gif.png` | Video to GIF wizard (palette quality question) |
| `processing.png` | Live progress while FFmpeg encodes |
| `completed.png` | Result screen with output path, size comparison and next actions |
