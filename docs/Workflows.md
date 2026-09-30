# Workflows and their options

Every workflow: choose input -> the file is probed (a *Source* panel shows container, duration, video/audio summary, size) ->
questions -> output folder / name / overwrite handling -> summary (`Enter` start, `V` view command, `Esc` back) -> run with progress ->
result (`O` open folder, `R` run again, `M` main menu) or failure (`D` details, `R` retry, `B` back).

Common questions (used by most workflows):

* **Output folder** - same folder as the source, or a typed folder; a missing folder is created only after confirmation.
* **Output file name** - default `<source>_<suffix>.<ext>`; the extension is added automatically; identical-to-source, illegal, reserved
  or over-long names are rejected; an existing file asks *Choose a different name* or *Overwrite*.
* **Video codec** - *Automatic*, *Copy original* (where allowed) and every supported encoder of your build that the chosen container can hold;
  detected hardware encoders appear only if a test encode succeeds. Quality mode: *Recommended*, *Quality level* (High / Balanced / Smaller / custom, range-checked
  per encoder) or *Target bitrate*; encoder preset when the encoder has one.
* **Audio** - keep (copy), convert automatically, choose an encoder, or remove; bitrate (or VBR quality for MP3/Vorbis), sample rate, channels.
* **Advanced options** - a gate question; expert settings are hidden unless you say yes.

## 1. Convert Video Format
Input video - output format (MP4, MKV, WebM, MOV, AVI, MPEG-TS, FLV as supported) - video codec / quality mode / quality / preset / bitrate -
resolution (keep, 4K, 1440p, 1080p, 720p, 480p, custom `WxH` or width) - frame rate (keep, 24/25/30/50/60, custom) - audio (copy/convert/remove, codec,
bitrate, sample rate, channels) - subtitles (copy compatible / remove) - metadata (preserve / strip) - advanced: pixel format, keyframe interval, faststart,
hardware decoding (off / automatic / detected) - output. Copy + resolution/frame-rate change and incompatible copy combinations are explained, not attempted.

## 2. Convert Audio Format
Input audio - format (MP3, M4A/AAC, FLAC, WAV, Opus, OGG, AAC, AC-3, MKA - only those your build can write) - codec - bitrate or VBR quality - sample rate -
channels - metadata - output.

## 3. Extract Audio from Video
Input video - audio track (asked only when several exist; language/title shown) - *copy original stream* (format chosen from the codec) or *convert* (format, codec,
bitrate/quality, sample rate, channels) - entire video or a range (start+end / start+duration) - output.

## 4. Trim / Cut Media
Input - start + end or start + duration (validated against the media length) - **Fast cut** (stream copy; may start at a keyframe) or **Accurate cut** (re-encode) -
output format - codec/quality when re-encoding - output. Works for video and audio.

## 5. Merge Media
Ordered file list (add, move up/down, remove) - compatibility inspection (codec, resolution, pixel format, frame rate, audio settings) - **lossless** concat when compatible or
**re-encode to common settings** (format, codec/quality, target resolution with black bars, audio) - output. The reason for re-encoding is shown. Mixed audio+video lists are refused.

## 6. Compress Media
Video: goal (*Smaller file / Recommended*, *Quality target*, *Target bitrate*, *Approximate target file size* - bitrate computed from duration and audio allowance, always called approximate) -
codec (incl. hardware) - preset - optional resolution / frame-rate reduction - audio (copy/convert/remove, bitrate) - output.
Audio: format, codec, bitrate/VBR, sample rate, channels. The result shows original vs new size.

## 7. Resize / Scale Video
Target (keep, 4K, 1440p, 1080p, 720p, 480p, custom) - aspect behavior: *Preserve* (default), *Fit inside*, *Fill/crop*, *Stretch* (only when chosen) - optional black-bar padding -
Advanced: scaling algorithm (bicubic default, Lanczos, bilinear, spline, nearest) - codec/quality - output. Audio is copied.

## 8. Video to GIF
Input - clip range (entire / start+end / start+duration) - frame rate (10/15/20/24/30/custom) - optional maximum frame count - speed (0.25x-2x, custom 0.1-8) -
width (keep, 320, 480, 640, 720, custom) - preserve aspect ratio (else an explicit height) - palette quality (**High Quality** = `palettegen` + `paletteuse`, **Fast**) -
number of colors (2-256) - dithering (Sierra 2-4A, Floyd-Steinberg, Bayer, none) - loop (infinite, once, N repeats) - output.

## 9. Extract Frames / Images
Mode (single frame at a time, every N seconds, N frames per second, time range) - image format (PNG, JPEG, WebP, BMP, TIFF as supported) - quality - image size -
optional maximum count - output folder - file-name prefix and zero-padding (the resulting name, e.g. `clip_frame_0001.png`, is shown before running).

## A. Audio Tools
1. **Adjust Volume** - preset, percentage or dB. 2. **Normalize Loudness** - EBU R128 `loudnorm`, two passes (*Analysis*, then *Processing*), targets -16 / -14 / -23 LUFS.
3. **Change Sample Rate** - common rates or custom. 4. **Change Channels** - mono, stereo, 5.1, 7.1, custom. 5. **Change Audio Speed / Tempo** - tempo (keeps pitch, chained `atempo`) or speed+pitch.
6. **Remove Audio from Video** - stream copy. 7. **Replace / Add Audio Track** - replace or add, start offset, keep video length or shortest, audio copy/encode, container.
(Tools 1-5 keep a video stream untouched when the input is a video, except tool 5 which is audio-only.)

## B. Subtitle Tools
1. **Extract** - choose stream; text subtitles -> SRT / ASS / WebVTT, bitmap -> Matroska subtitles. 2. **Add / Mux** - subtitle file, language, title, default flag, container (mov_text for MP4/MOV);
audio/video copied. 3. **Burn** - file or embedded stream, text size, position; re-encodes the video (needs `subtitles`/libass). 4. **Remove** all subtitle streams (copy). 5. **Copy selected** subtitle streams.

## C. Change Frame Rate
Target FPS (common or custom; the current rate is shown) - *Standard* (drop/duplicate) or *Motion interpolation* (`minterpolate`, only if available; explained as slow and synthetic) - codec/quality - output.

## D. Filters & Color
Select any of: brightness, contrast, saturation, gamma, grayscale, sharpen, blur, fade in, fade out - set each strength (presets or validated custom values) -
Advanced: an expert filter expression that is test-run by FFmpeg before it is accepted - the chain is shown as readable labels. **Filter Browser** searches the names/descriptions of the filters in your build.

## E. Crop / Rotate / Flip
Crop: aspect preset (16:9, 4:3, 1:1, 9:16, 21:9, centered), centered custom size, or size + X/Y - validated against the source (even dimensions, inside the frame). Rotate: 90 cw / 90 ccw / 180 / custom angle.
Flip: horizontal / vertical / both.

## F. Text & Watermark
Add Text: text (any characters), font (default or a font file), size, position preset (or exact X/Y in Advanced), color, opacity, optional background box, start/end time. The text is passed via a temporary file, not the command line.
Watermark: logo image, position preset, margin, size (% of video width), opacity, optional start/end time.

## G. Change Playback Speed
Speed (0.25x-2x or custom 0.1-10) - for slow motion: duplicate frames or interpolation - audio kept synchronized (chained `atempo` for values outside 0.5-2) or removed - codec/quality - output. Audio-only files are supported.

## H. Streaming / HLS
1. **Create HLS Output** - output folder, playlist name, segment length, copy or re-encode (H.264 + AAC), playlist type (VOD/Event), segment name pattern; playlist and segments stay together in the folder.
2. **Read / Save Network Stream** - validated address (only network protocols reported by your build), optional length limit, save as MKV/MP4/TS (no re-encoding); credentials are never echoed.
3. **Inspect Stream Information** - a stream address or local file.

## I. Media Information
Sections *File, Video, Audio, Subtitles, Metadata, Streams*; `T` opens a formatted *Technical details* view; `N` inspects another file.

## S. FFmpeg Status / Settings
Paths, version, PowerShell version, terminal capabilities, hardware accelerators, capability-cache status, package-manager and update status. Actions: `C` re-scan capabilities, `U` check for updates, `P` re-detect FFmpeg paths, `B` back.
