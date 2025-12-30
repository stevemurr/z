#!/usr/bin/env zsh

ffmpeg-get-audio() {
  local file
  file=$(find . -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" \) | fzf)
  [[ -z "$file" ]] && return
  local out="${file%.*}.mp3"
  ffmpeg -i "$file" -q:a 0 -map a "$out"
  echo "Extracted audio to $out"
}

ffmpeg-convert() {
  local file
  file=$(find . -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" \) | fzf --preview 'ffprobe -v error -show_entries format=duration:stream=width,height,codec_name -of default=noprint_wrappers=1:nokey=1 {}')
  [[ -z "$file" ]] && return
  read "format?Convert to format (e.g. mp3, mp4, gif): "
  local out="${file%.*}.$format"
  ffmpeg -i "$file" "$out"
  echo "Converted $file to $out"
}

