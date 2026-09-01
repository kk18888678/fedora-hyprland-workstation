# Advanced Media Tools Environment

Reproducible development and CLI processing environment for multimedia workflows.

## Purpose

Provides specialized media processing and inspection utilities without polluting the host Fedora OS:

- `ffmpeg` / `ffprobe`: Video/audio transcoding and stream inspection
- `mediainfo`: Detailed media container and codec metadata analysis
- `mkvtoolnix`: Matroska multiplexing and extraction (`mkvmerge`, `mkvextract`, `mkvinfo`)
- `gpac`: MP4Box container manipulation and ISO media processing
- `ccextractor`: Closed caption and subtitle extraction
- `bento4`: Fast MP4 multiplexing, fragmentation, and DRM tooling (`mp4dump`, `mp4fragment`, `mp4split`)
- `shaka-packager`: DASH/HLS packaging, encryption, and streaming manifest generation
- `dovi-tool`: Dolby Vision RPU extraction, editing, and injection (`dovi_tool`)
- `n-m3u8dl-re`: Cross-platform CLI DASH/HLS/MSS stream downloader (`N_m3u8DL-RE`)

## Usage

Enter this isolated environment anytime using `devenv`:

```bash
cd environments/media-tools
devenv shell
```

Or run commands directly without entering a subshell:

```bash
devenv shell -- MP4Box -info video.mp4
```
