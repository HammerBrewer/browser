#!/usr/bin/env bash
set -euo pipefail

# ====================================================
# NO VNC + CHROME + AUTO-UPLOAD TO GOOGLE DRIVE
# ====================================================

# -----------------------------
# CONFIGURATION
# -----------------------------
DOWNLOAD_DIR="$HOME/Downloads"
REMOTE="gdrive:youtube_downloads"       # Change this to your remote folder
LOG_FILE="$HOME/auto_upload.log"
RCLONE_CONF="$HOME/workspaces/browser/rclone.conf"  # Preconfigured rclone.conf in repo

# Ensure directories exist
mkdir -p "$DOWNLOAD_DIR"
touch "$LOG_FILE"

# Set Rclone to use the pre-configured file
export RCLONE_CONFIG="$RCLONE_CONF"

echo "=============================="
echo " NO VNC + CHROME (SAFE MODE) WITH AUTO GDRIVE UPLOAD"
echo "=============================="

# -----------------------------
# 1. CLEAN PORTS SAFELY
# -----------------------------
echo "[1/10] Cleaning old processes on ports 5901 and 6080..."
for p in 5901 6080; do
  if lsof -ti :$p >/dev/null 2>&1; then
    echo "Killing process on port $p"
    lsof -ti :$p | xargs kill -9 || true
  fi
done

# -----------------------------
# 2. INSTALL DEPENDENCIES
# -----------------------------
echo "[2/10] Installing packages..."
sudo apt update -y
sudo apt install -y \
  wget curl git \
  openbox x11vnc xvfb \
  novnc websockify \
  dbus-x11 fonts-liberation unzip zip inotify-tools \
  python3-pip

# -----------------------------
# 3. INSTALL CHROME
# -----------------------------
echo "[3/10] Installing Google Chrome..."
if ! command -v google-chrome >/dev/null 2>&1; then
  wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | \
    sudo tee /etc/apt/sources.list.d/google-chrome.list
  sudo apt update -y
  sudo apt install -y google-chrome-stable
fi

# -----------------------------
# 4. START VIRTUAL DISPLAY
# -----------------------------
echo "[4/10] Starting virtual display..."
export DISPLAY=:1
Xvfb :1 -screen 0 1280x800x16 > /dev/null 2>&1 &
sleep 2

# -----------------------------
# 5. START OPENBOX
# -----------------------------
echo "[5/10] Starting window manager..."
openbox > /dev/null 2>&1 &

# -----------------------------
# 6. START VNC
# -----------------------------
echo "[6/10] Starting VNC server..."
x11vnc -display :1 -nopw -forever -shared -rfbport 5901 \
  > /dev/null 2>&1 &

# -----------------------------
# 7. START NOVNC
# -----------------------------
echo "[7/10] Starting noVNC server..."
websockify --web=/usr/share/novnc 6080 localhost:5901 \
  > /dev/null 2>&1 &

# -----------------------------
# 8. START CHROME
# -----------------------------
echo "[8/10] Launching Chrome..."
google-chrome \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --user-data-dir="$HOME/.chrome" \
  --disable-background-networking \
  --disable-default-apps \
  --disable-extensions \
  --disable-sync \
  --display=:1 \
  --window-size=1280,800 \
  https://www.google.com \
  > /dev/null 2>&1 &

# -----------------------------
# 9. AUTO-UPLOAD WATCHER
# -----------------------------
echo "[9/10] Starting auto-upload watcher for Downloads..."

(
  inotifywait -m -e close_write,moved_to --format '%f' "$DOWNLOAD_DIR" | while read FILE; do
    FULL_PATH="$DOWNLOAD_DIR/$FILE"

    # Skip hidden/temp files or incomplete downloads
    if [[ "$FILE" == .* ]] || [[ "$FILE" == *.crdownload ]] || [[ "$FILE" == *.part ]]; then
      continue
    fi

    if [[ -f "$FULL_PATH" ]]; then
      # Generate timestamp + random 5-digit filename
      EXT="${FILE##*.}"
      NEW_NAME="$(date +%Y%m%d%H%M%S)_$((RANDOM%90000+10000)).$EXT"
      TEMP_PATH="$DOWNLOAD_DIR/$NEW_NAME"

      # Rename the file to avoid collisions
      mv "$FULL_PATH" "$TEMP_PATH" || continue

      echo "$(date '+%Y-%m-%d %H:%M:%S') Uploading $TEMP_PATH -> $REMOTE/$NEW_NAME" | tee -a "$LOG_FILE"

      # Upload with retry
      for i in {1..3}; do
        if rclone copy "$TEMP_PATH" "$REMOTE/" --progress; then
          echo "$(date '+%Y-%m-%d %H:%M:%S') Upload successful: $NEW_NAME" | tee -a "$LOG_FILE"
          rm -f "$TEMP_PATH"
          break
        else
          echo "$(date '+%Y-%m-%d %H:%M:%S') Upload failed (attempt $i), retrying..." | tee -a "$LOG_FILE"
          sleep 2
        fi
      done
    fi
  done
) &

# -----------------------------
# 10. READY
# -----------------------------
echo "[10/10] Setup complete!"
echo "=============================="
echo "Open:"
echo "👉 Codespaces → PORT 6080 → Open in Browser"
echo ""
echo "Everything downloaded in Chrome will now:"
echo "- Be renamed with timestamp+random number"
echo "- Auto-uploaded to Google Drive ($REMOTE)"
echo "- Removed locally after successful upload"
echo ""
echo "Upload log: $LOG_FILE"