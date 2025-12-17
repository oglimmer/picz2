#!/bin/bash
# Generate thumbnail images from existing videos
# This extracts the first frame at 1 second for preview

cd ./server/uploads

count=0
for file in *.mov *.mp4; do
  # Skip if file doesn't exist (handles no matches)
  if [ ! -f "$file" ]; then
    continue
  fi

  # Skip web_*.mp4 files (transcoded versions)
  if [[ "$file" == web_* ]]; then
    continue
  fi

  # Generate thumbnail filename
  base_name="${file%.*}"
  thumbnail="thumb_${base_name}.jpg"

  # Skip if thumbnail already exists
  if [ -f "$thumbnail" ]; then
    echo "Skipping $file (thumbnail exists)"
    continue
  fi

  echo "Generating thumbnail: $file -> $thumbnail"
  ffmpeg -ss 1 -i "$file" \
    -vframes 1 \
    -vf "scale=600:-1" \
    -q:v 2 \
    -y \
    "$thumbnail" 2>&1 | grep -v "^frame=" | grep -v "^Stream" | grep -v "^Input" | grep -v "^Duration" | grep -v "^Metadata"

  if [ $? -eq 0 ] && [ -f "$thumbnail" ]; then
    echo "✓ Generated thumbnail for $file"
    count=$((count + 1))
  else
    echo "✗ Failed to generate thumbnail for $file"
  fi
done

echo ""
echo "Generated $count video thumbnails"
echo "Next: Update database to link thumbnails"
echo "  curl -X POST http://localhost:8080/api/admin/update-video-thumbnails -u your-email:password"
