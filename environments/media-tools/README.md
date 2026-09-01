# Advanced Media Tools Environment

Reproducible development and CLI processing environment for multimedia workflows.

## Purpose

Provides specialized media processing and inspection utilities without polluting the host Fedora OS:

- `ffmpeg` / `ffprobe`: Video/audio transcoding and stream inspection
- `mediainfo`: Detailed media container and codec metadata analysis
- `mkvtoolnix`: Matroska multiplexing and extraction (`mkvmerge`, `mkvextract`, `mkvinfo`)
- `gpac`: MP4Box container manipulation and ISO media processing
- `ccextractor`: Closed caption and subtitle extraction

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
