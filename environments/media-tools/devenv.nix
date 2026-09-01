{ pkgs, ... }:

{
  # Advanced media processing environment.
  # Provides specialized media analysis, subtitle extraction, Dolby Vision manipulation,
  # HLS/DASH downloading, and MP4/Matroska packaging CLI tools without polluting the host Fedora OS.
  packages = [
    pkgs.ffmpeg
    pkgs.mediainfo
    pkgs.mkvtoolnix
    pkgs.gpac
    pkgs.ccextractor
    pkgs.bento4
    pkgs."shaka-packager"
    pkgs."dovi-tool"
    pkgs."n-m3u8dl-re"
  ];

  enterShell = ''
    echo "Media processing development environment loaded."
    echo "Available tools: ffmpeg, mediainfo, mkvmerge, MP4Box, ccextractor, mp4dump, packager, dovi_tool, N_m3u8DL-RE"
  '';
}
