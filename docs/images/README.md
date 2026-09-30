# Screenshots

These images show the **real application**: each one is a frame of the actual terminal output of `Start-FFmpegTUI.ps1` (version in the window title bar / header)
while it processed a real 40-second 720p test video.

How they were captured (honest note): the app was driven through a pseudo-terminal in a **Linux** environment (PowerShell 7.4, FFmpeg 6.1), the ANSI output was
interpreted by a terminal emulator library and drawn with a monospace font in a headless browser. Nothing was mocked up or edited by hand.
Windows Terminal will look very similar but fonts, emoji and window chrome differ slightly. Native Windows captures can replace these files at any time
(keep the same file names).

| File | Screen |
|---|---|
| `main-menu.png` | Main menu |
| `ffmpeg-status.png` | FFmpeg Status / Settings (detected tools, capabilities, update status) |
| `conversion-wizard.png` | A wizard question (Convert Video Format, output format) with the *Source* panel |
| `video-to-gif.png` | Video to GIF wizard (palette quality question) |
| `processing.png` | Live progress while FFmpeg encodes |
| `completed.png` | Result screen with output path, size comparison and next actions |
