#!/usr/bin/env bash
set -e

# --- CONFIG ---
DOWNLOAD_DIR="./downloads"
mkdir -p "$DOWNLOAD_DIR"

# --- INPUT ---
read -p "Enter YouTube URL: " URL
if [[ -z "$URL" ]]; then
  echo "Error: No URL provided"
  exit 1
fi

# --- RANDOM FILENAME ---
RAND=$(shuf -i 10000-99999 -n 1)
ZIP_FILE="$DOWNLOAD_DIR/$RAND.zip"

# --- DOWNLOAD VIDEO ---
echo "Downloading video..."
# Install yt-dlp if missing
if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "yt-dlp not found. Installing..."
  python3 -m pip install --user yt-dlp
  export PATH="$HOME/.local/bin:$PATH"
fi

VIDEO_FILE="$DOWNLOAD_DIR/$RAND.mp4"

yt-dlp -f best -o "$VIDEO_FILE" "$URL"

# --- ZIP IT ---
echo "Zipping video..."
zip -j "$ZIP_FILE" "$VIDEO_FILE"

# --- CLEANUP ---
rm "$VIDEO_FILE"

echo "✅ Done! Your file is: $ZIP_FILE"
echo "You can download it from your Codespace."