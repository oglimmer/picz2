#!/bin/bash
# Rename existing MP4 files to match the web_ naming convention

cd ./server/uploads

count=0
for file in *.mp4; do
  if [ -f "$file" ]; then
    # Skip files that already have web_ prefix
    if [[ "$file" == web_* ]]; then
      echo "Skipping $file (already has web_ prefix)"
      continue
    fi

    # Check if corresponding .mov file exists (to ensure it's a transcoded video)
    mov_file="${file%.mp4}.mov"
    if [ ! -f "$mov_file" ]; then
      echo "Skipping $file (no corresponding .mov file found)"
      continue
    fi

    new_name="web_$file"

    # Skip if web_ version already exists
    if [ -f "$new_name" ]; then
      echo "Skipping $file (web_ version already exists)"
      continue
    fi

    echo "Renaming: $file -> $new_name"
    mv "$file" "$new_name"

    if [ $? -eq 0 ]; then
      echo "✓ Renamed $file"
      count=$((count + 1))
    else
      echo "✗ Failed to rename $file"
    fi
  fi
done

echo ""
echo "Renamed $count files"
echo "Next step: Run the database update script or restart the server with the admin endpoint"
