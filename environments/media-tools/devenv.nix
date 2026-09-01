{ pkgs, ... }:

{
  # Advanced media processing environment.
  # Provides specialized media analysis, subtitle extraction, and packaging CLI tools
  # without polluting the host Fedora OS.
  packages = [
    pkgs.ffmpeg
    pkgs.mediainfo
    pkgs.mkvtoolnix
    pkgs.gpac
    pkgs.ccextractor
  ];

  enterShell = ''
    echo "Media processing development environment loaded."
    echo "Available tools: ffmpeg, mediainfo, mkvmerge, MP4Box, ccextractor"
  '';
}
