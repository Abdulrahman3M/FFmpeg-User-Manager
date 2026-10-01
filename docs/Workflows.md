# Workflows and their options

## How every screen works

* Every option on every screen is shown as **Number, Icon, Name** with a short description underneath, for example `06  [icon]  Compress Media`.
  Numbers are two digits and zero-padded (`01`, `02` ... `09`, `10`, `11` ...) and simply continue past `99` (`100`, `101` ...) when a list is that long.
  There are **no letter keys** - not even for Exit or Back.
* Type the number to choose an option (`05` selects option 5 at once; a single digit that cannot start a longer number, such as `5` in a list of 12, also works; for a
  longer prefix such as `1` in a list of 12, type the next digit or press `Enter`). `Up`/`Down` + `Enter` work too.
* `Esc` goes back one step (answers are kept). `Ctrl+C` quits the application. `Enter` accepts the highlighted option or the default.
* Yes/No questions are numbered lists too: `01` = the first answer, `02` = the second (the labels say what each does).
* Every question shows what to enter or choose, and typed questions show an example.

Every wizard: choose input -> the file is probed (a *Source* panel shows container, duration, video/audio summary, size) -> questions -> output folder / name /
overwrite handling -> summary (`01 Start`, `02 View FFmpeg command (Advanced)`, `03 Back`) -> run with progress (`Esc` cancels after confirmation) ->
result (*Open output folder*, *Run again*, *Main menu*) or failure (*Show technical details*, *Retry*, *Back*).

Common questions (used by most workflows):

* **Output folder** - same folder as the source, or a typed folder; a missing folder is created only after confirmation.
* **Output file name** - default `<source>_<suffix>.<ext>`; the extension is added automatically; identical-to-source, illegal, reserved
  or over-long names are rejected; an existing file asks *Choose a different name* or *Overwrite*.
* **Video codec** - *Automatic*, *Copy original* (where allowed) and every supported encoder of your build that the chosen container can hold;
  detected hardware encoders appear only if a test encode succeeds. Quality mode: *Recommended*, *Quality level* (High / Balanced / Smaller / custom, range-checked
  per encoder) or *Target bitrate*; encoder preset when the encoder has one.
* **Audio** - keep (copy), convert automatically, choose an encoder, or remove; bitrate (or VBR quality for MP3/Vorbis), sample rate, channels.
* **Advanced options** - a gate question; expert settings are hidden unless you say yes.

## Main menu

| No. | Option | Section |
|---|---|---|
| 01 | Convert Video Format | [1](#01-convert-video-format) |
| 02 | Convert Audio Format | [2](#02-convert-audio-format) |
| 03 | Extract Audio from Video | [3](#03-extract-audio-from-video) |
| 04 | Trim / Cut Media | [4](#04-trim--cut-media) |
| 05 | Merge Media | [5](#05-merge-media) |
| 06 | Compress Media | [6](#06-compress-media) |
| 07 | Resize / Scale Video | [7](#07-resize--scale-video) |
| 08 | Video to GIF | [8](#08-video-to-gif) |
| 09 | Extract Frames / Images | [9](#09-extract-frames--images) |
| 10 | Audio Tools | [10](#10-audio-tools) |
| 11 | Subtitle Tools | [11](#11-subtitle-tools) |
| 12 | Change Frame Rate | [12](#12-change-frame-rate) |
| 13 | Filters & Color | [13](#13-filters--color) |
| 14 | Crop / Rotate / Flip | [14](#14-crop--rotate--flip) |
| 15 | Text & Watermark | [15](#15-text--watermark) |
| 16 | Change Playback Speed | [16](#16-change-playback-speed) |
| 17 | Streaming / HLS | [17](#17-streaming--hls) |
| 18 | Media Information | [18](#18-media-information) |
| 19 | Remux & Streams | [19](#19-remux--streams) |
| 20 | Metadata & Chapters | [20](#20-metadata--chapters) |
| 21 | Images & Slideshows | [21](#21-images--slideshows) |
| 22 | Video Enhancement | [22](#22-video-enhancement) |
| 23 | Record / Capture | [23](#23-record--capture) |
| 24 | Analyze & Detect | [24](#24-analyze--detect) |
| 25 | Batch Convert Folder | [25](#25-batch-convert-folder) |
| 26 | Advanced FFmpeg | [26](#26-advanced-ffmpeg) |
| 27 | FFmpeg Status / Settings | [27](#27-ffmpeg-status--settings) |
| 28 | Check & Maintain FFmpeg Setup | [28](#28-check--maintain-ffmpeg-setup) |
| 29 | Exit | closes the application |

## FFmpeg capability coverage

The guided tools cover the main practical FFmpeg categories; everything else is reachable in an organized way through **26 Advanced FFmpeg** instead of a button per codec or filter.
Options whose encoder, filter, muxer or protocol is missing from the installed build are shown disabled with the reason (or not offered).

| FFmpeg category | Where |
|---|---|
| Video / audio conversion and transcoding, codecs and containers | 01, 02, 06, 25 (batch), 26 (any encoder/format via the custom command) |
| Remuxing (container change without re-encoding) | 19 |
| Trimming, cutting, joining | 04, 05 |
| Decoding / encoding, hardware acceleration | 01 and 06 (hardware decoding and GPU encoders, tested before they are offered), 26 (hardware check) |
| Resolution, scaling, cropping, rotation, padding | 07, 14, 22 (add bars) |
| Frame rate, speed, reverse, loop | 12, 16, 22 |
| Bitrate, quality, compression, target size | 01, 06 |
| Audio extraction, volume, channels, sample rate, loudness, effects | 03, 10 |
| Filters and color, denoise, deinterlace, stabilize, fades | 13, 22, 26 (filter browser) |
| Images, image sequences, GIF, thumbnails | 08, 09, 21 |
| Subtitles | 11 |
| Metadata, chapters, cover art | 20 |
| Streams and stream mapping (keep selected, language, default track) | 19, 26 |
| Recording / capture (screen, webcam, microphone) | 23 |
| Streaming and network (HLS, save a stream, send a file out) | 17 |
| Analysis and probing (media info, volume, loudness, silence, black frames, scenes, crop, quality) | 18, 24 |
| Batch processing | 25 |
| Anything else | 26 |

## 01 Convert Video Format
Input video - output format (MP4, MKV, WebM, MOV, AVI, MPEG-TS, FLV as supported) - video codec / quality mode / quality / preset / bitrate -
resolution (keep, 4K, 1440p, 1080p, 720p, 480p, custom `WxH` or width) - frame rate (keep, 24/25/30/50/60, custom) - audio (copy/convert/remove, codec,
bitrate, sample rate, channels) - subtitles (copy compatible / remove) - metadata (preserve / strip) - advanced: pixel format, keyframe interval, faststart,
hardware decoding (off / automatic / detected) - output. Copy + resolution/frame-rate change and incompatible copy combinations are explained, not attempted.

## 02 Convert Audio Format
Input audio - format (MP3, M4A/AAC, FLAC, WAV, Opus, OGG, AAC, AC-3, MKA - only those your build can write) - codec - bitrate or VBR quality - sample rate -
channels - metadata - output.

## 03 Extract Audio from Video
Input video - audio track (asked only when several exist; language/title shown) - *copy original stream* (format chosen from the codec) or *convert* (format, codec,
bitrate/quality, sample rate, channels) - entire video or a range (start+end / start+duration) - output.

## 04 Trim / Cut Media
Input - start + end or start + duration (validated against the media length) - **Fast cut** (stream copy; may start at a keyframe) or **Accurate cut** (re-encode) -
output format - codec/quality when re-encoding - output. Works for video and audio.

## 05 Merge Media
Ordered file list (add, move up/down, remove) - compatibility inspection (codec, resolution, pixel format, frame rate, audio settings) - **lossless** concat when compatible or
**re-encode to common settings** (format, codec/quality, target resolution with black bars, audio) - output. The reason for re-encoding is shown. Mixed audio+video lists are refused.

## 06 Compress Media
Video: goal (*Smaller file / Recommended*, *Quality target*, *Target bitrate*, *Approximate target file size* - bitrate computed from duration and audio allowance, always called approximate) -
codec (incl. hardware) - preset - optional resolution / frame-rate reduction - audio (copy/convert/remove, bitrate) - output.
Audio: format, codec, bitrate/VBR, sample rate, channels. The result shows original vs new size.

## 07 Resize / Scale Video
Target (keep, 4K, 1440p, 1080p, 720p, 480p, custom) - aspect behavior: *Preserve* (default), *Fit inside*, *Fill/crop*, *Stretch* (only when chosen) - optional black-bar padding -
Advanced: scaling algorithm (bicubic default, Lanczos, bilinear, spline, nearest) - codec/quality - output. Audio is copied.

## 08 Video to GIF
Input - clip range (entire / start+end / start+duration) - frame rate (10/15/20/24/30/custom) - optional maximum frame count - speed (0.25x-2x, custom 0.1-8) -
width (keep, 320, 480, 640, 720, custom) - preserve aspect ratio (else an explicit height) - palette quality (**High Quality** = `palettegen` + `paletteuse`, **Fast**) -
number of colors (2-256) - dithering (Sierra 2-4A, Floyd-Steinberg, Bayer, none) - loop (infinite, once, N repeats) - output.

## 09 Extract Frames / Images
Mode (single frame at a time, every N seconds, N frames per second, time range) - image format (PNG, JPEG, WebP, BMP, TIFF as supported) - quality - image size -
optional maximum count - output folder - file-name prefix and zero-padding (the resulting name, e.g. `clip_frame_0001.png`, is shown before running).

## 10 Audio Tools
A submenu of 14 tools:

1. **Adjust Volume** - preset, percentage or dB. 2. **Normalize Loudness** - EBU R128 `loudnorm`, two passes (*Analysis*, then *Processing*), targets -16 / -14 / -23 LUFS.
3. **Change Sample Rate** - common rates or custom. 4. **Change Channels** - mono, stereo, 5.1, 7.1, custom. 5. **Change Audio Speed / Tempo** - tempo (keeps pitch, chained `atempo`) or speed+pitch.
6. **Remove Audio from Video** - stream copy. 7. **Replace / Add Audio Track** - replace or add, start offset, keep video length or shortest, audio copy/encode, container.
8. **Fade In / Fade Out** (`afade`). 9. **Bass / Treble / Voice Clarity** (`bass`, `treble`, `equalizer`). 10. **Reduce Background Noise** (`afftdn`).
11. **Remove Silence** (`silenceremove`, audio files only). 12. **Remove Rumble / Hiss** - frequency filter (`highpass`, `lowpass`). 13. **Fix Audio / Video Sync** - shift the sound earlier or later
(`adelay` / `atrim`). 14. **Reverse Audio** (`areverse`, up to 10 minutes).
A video input keeps its picture untouched (stream copy) in tools 1-4 and 8-13.

## 11 Subtitle Tools
1. **Extract** - choose stream; text subtitles -> SRT / ASS / WebVTT, bitmap -> Matroska subtitles. 2. **Add / Mux** - subtitle file, language, title, default flag, container (mov_text for MP4/MOV);
audio/video copied. 3. **Burn** - file or embedded stream, text size, position; re-encodes the video (needs `subtitles`/libass). 4. **Remove** all subtitle streams (copy). 5. **Copy selected** subtitle streams.

## 12 Change Frame Rate
Target FPS (common or custom; the current rate is shown) - *Standard* (drop/duplicate) or *Motion interpolation* (`minterpolate`, only if available; explained as slow and synthetic) - codec/quality - output.

## 13 Filters & Color
Select any of: brightness, contrast, saturation, gamma, grayscale, sharpen, blur, fade in, fade out - set each strength (presets or validated custom values) -
Advanced: an expert filter expression that is test-run by FFmpeg before it is accepted - the chain is shown as readable labels. **Filter Browser** searches the names/descriptions of the filters in your build.

## 14 Crop / Rotate / Flip
Crop: aspect preset (16:9, 4:3, 1:1, 9:16, 21:9, centered), centered custom size, or size + X/Y - validated against the source (even dimensions, inside the frame). Rotate: 90 cw / 90 ccw / 180 / custom angle.
Flip: horizontal / vertical / both.

## 15 Text & Watermark
Add Text: text (any characters), font (default or a font file), size, position preset (or exact X/Y in Advanced), color, opacity, optional background box, start/end time. The text is passed via a temporary file, not the command line.
Watermark: logo image, position preset, margin, size (% of video width), opacity, optional start/end time.

## 16 Change Playback Speed
Speed (0.25x-2x or custom 0.1-10) - for slow motion: duplicate frames or interpolation - audio kept synchronized (chained `atempo` for values outside 0.5-2) or removed - codec/quality - output. Audio-only files are supported.

## 17 Streaming / HLS
1. **Create HLS Output** - output folder, playlist name, segment length, copy or re-encode (H.264 + AAC), playlist type (VOD/Event), segment name pattern; playlist and segments stay together in the folder.
2. **Read / Save Network Stream** - validated address (only network protocols reported by your build), optional length limit, save as MKV/MP4/TS (no re-encoding); credentials are never echoed.
3. **Send a File to a Network Address (Stream Out)** - play a file in real time to an RTMP, RTMPS, SRT, UDP, TCP, RTP or RTSP address (only those your build can write); re-encode to H.264 + AAC or copy (H.264 + AAC sources); the stream key is hidden on screen.
4. **Inspect Stream Information** - a stream address or local file.

## 18 Media Information
Sections *File, Video, Audio, Subtitles, Metadata, Streams*; `Enter` opens *More actions*: a formatted *Technical details* view or *Inspect another file*.

## 19 Remux & Streams
Nothing is re-encoded, so these are fast and lossless.
1. **Remux** - new container (MP4, MKV, WebM, MOV, ... or an audio container for audio-only files); codecs that the new container cannot hold are explained.
2. **Keep Selected Streams** - tick the video, audio and subtitle streams to keep (language and title shown); everything else is dropped.
3. **Set Track Language / Default Track** - three-letter language code and/or make a track the default of its kind (other tracks lose the flag).

## 20 Metadata & Chapters
1. **Edit Metadata** - title, artist, album, genre, year, comment (empty fields keep the current value). 2. **Remove Metadata / Chapters** - everything, tags only, or chapters only.
3. **Add Chapters** - a list such as `00:00:00 Intro; 00:02:30 Main part` (validated: increasing times, inside the media) for MKV/MP4/M4A/M4B/MOV files.
4. **Attach Cover Art** - a JPG/PNG picture embedded in an MP3, M4A or FLAC file. All four copy the streams.

## 21 Images & Slideshows
1. **Pictures to Slideshow Video** - ordered picture list, seconds per picture, video size (pictures are fitted, never stretched), frame rate, optional background music, format/codec.
2. **Numbered Image Sequence to Video** - pattern such as `frame_%04d.png`, first number, frame rate, format/codec (animation, time-lapse).
3. **Audio to Video** - a still picture, animated sound waves (`showwaves`), a scrolling spectrum (`showspectrum`) or a black screen, for sites that only accept video.
4. **Contact Sheet** - columns x rows of evenly spaced thumbnails of a video as one JPG/PNG.

## 22 Video Enhancement
1. **Deinterlace** (`yadif` or `bwdif`). 2. **Reduce Video Noise** (`hqdn3d`, light/medium/strong). 3. **Stabilize Shaky Video** (two passes with `vidstabdetect` / `vidstabtransform`, needs libvidstab).
4. **Add Bars to Fit an Aspect Ratio** (16:9, 4:3, 1:1, 9:16, 21:9; letterbox/pillarbox, no cropping). 5. **Reverse Video** (up to 2 minutes). 6. **Loop (Repeat) a Clip** (no re-encoding).
Each asks for container, codec and quality like the other video tools (except loop).

## 23 Record / Capture
Windows only (needs `gdigrab` and/or `dshow` in your FFmpeg build; otherwise the options are shown disabled with the reason). Every recording has a fixed length so the file is finished cleanly.
1. **Record the Screen** - length, frames per second, mouse pointer, optional microphone. 2. **Record from a Webcam** - camera and optional microphone (devices are read from FFmpeg). 3. **Record Audio from a Microphone** - WAV/MP3/M4A/... 4. **List Capture Devices**.

## 24 Analyze & Detect
Read-only: each tool runs FFmpeg filters to a null output and shows a report; no file is written or changed.
1. **Measure Volume** (mean/peak, clipping warning). 2. **Measure Loudness (LUFS)**. 3. **Detect Silence** (gaps with times). 4. **Detect Black Frames**. 5. **Detect Scene Changes** (cut times).
6. **Detect Black Bars** (suggests the crop). 7. **Compare Video Quality** (PSNR and SSIM of a converted video against the original).

## 25 Batch Convert Folder
Folder - include sub-folders - video or audio files (counts shown) - target format, codec and quality - output folder (default: a `Converted` folder inside the source folder) -
if a converted file exists: *Skip* (default) or *Overwrite*. Uses exactly the same job builders as single-file conversion; one progress stage per file. Originals are never touched; up to 500 files per batch.

## 26 Advanced FFmpeg
1. **Capability Browser** - search encoders, decoders, output/input formats, filters, protocols, hardware accelerators and pixel formats of your build; a single match opens FFmpeg's own help for it.
2. **Custom FFmpeg Command (Guided)** - input files, options for the first input, options for the output (quote values with spaces), output name with extension. Arguments are passed as separate tokens (never through a shell);
`-i`, `-y`, `-n`, `-progress` are refused; encoders/decoders/formats that your build lacks are rejected before running; overwrite handling stays with the application.
3. **Hardware Acceleration Check** - lists decoding methods and test-encodes every GPU encoder to show which are really usable. 4. **FFmpeg Build Details** - version and configuration.

## 27 FFmpeg Status / Settings
Paths, version, PowerShell version, terminal capabilities and icon set, hardware accelerators, capability-cache status, package-manager and update status. Actions (numbered): *Re-scan capabilities*,
*Check for updates*, *Re-detect FFmpeg paths*, *Icon style (emoji or symbols)*, *Back*.

## 28 Check & Maintain FFmpeg Setup
A guided health check in five steps. Before each step you are told what it does, shown an example and told whether the internet is used; nothing is downloaded or installed unless you say yes to that step.
1. **FFmpeg and ffprobe** - found and really started; if missing or broken you may install them with winget. 2. **FFmpeg updates** - asks winget; updating asks again.
3. **Emoji font** - checks that Segoe UI Emoji (part of Windows 10/11) exists; if it does not, the tool explains and suggests the symbol icons (no download, no system repair); it also reports whether Windows Terminal was detected. 4. **Icon style** - emoji or symbols, with a preview.
5. **Capability re-scan**. A summary lists what was checked, repaired or skipped.
