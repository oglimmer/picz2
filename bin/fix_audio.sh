#!/usr/bin/env bash
# Re-encode all .webm audio files in a directory using Opus codec

# Usage: ./reencode_webm.sh /path/to/folder
# If no path is given, use current directory
DIR="${1:-.}/server/uploads/recordings"

# Ensure directory exists
if [[ ! -d "$DIR" ]]; then
  echo "Error: Directory '$DIR' does not exist."
  exit 1
fi

# Loop through all .webm files
for f in "$DIR"/*.webm; do
  # Check if files exist
  [[ -e "$f" ]] || { echo "No .webm files found in '$DIR'"; exit 0; }

  echo "Processing: $f"

  # Temporary output file
  tmp="${f%.webm}_tmp.webm"

  # Re-encode
  ffmpeg -y -fflags +genpts -i "$f" \
    -c:a libopus -b:a 64k \
    -vbr on -application audio \
    -avoid_negative_ts make_zero \
    "$tmp"

  if [[ $? -eq 0 ]]; then
    # Replace original file
    mv -f "$tmp" "$f"
    echo "✅ Replaced original file: $f"
  else
    echo "❌ Error re-encoding: $f"
    # Clean up temp file if failed
    rm -f "$tmp"
  fi
done
