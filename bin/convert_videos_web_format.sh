#!/bin/bash
# Convert videos to Safari/iOS-compatible format with web_ prefix
# This matches the naming convention used by the Java code

cd ./server/uploads

count=0
for file in *.mov; do
  if [ -f "$file" ]; then
    # Generate output filename with web_ prefix and .mp4 extension
    base_name="${file%.mov}"
    output="web_${base_name}.mp4"

    # Skip if web_*.mp4 already exists
    if [ -f "$output" ]; then
      echo "Skipping $file (web_*.mp4 already exists)"
      continue
    fi

    echo "Converting: $file -> $output"
    ffmpeg -i "$file" \
      -c:v libx264 -profile:v main -level 4.0 -preset medium \
      -c:a aac -b:a 128k \
      -movflags +faststart \
      "$output"

    if [ $? -eq 0 ]; then
      echo "✓ Converted $file"
      count=$((count + 1))
    else
      echo "✗ Failed to convert $file"
    fi
  fi
done

echo ""
echo "Converted $count files"
echo "Run the admin endpoint to update the database: POST /api/admin/update-transcoded-videos"
