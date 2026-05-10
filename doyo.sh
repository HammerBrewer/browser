#!/usr/bin/env bash
set -euo pipefail

echo "=============================="
echo " Suwayomi Docker + GUI + GDrive"
echo "=============================="

DOWNLOADS_DIR="$HOME/Downloads"
RCLONE_REMOTE="gdrive"  # Change this if your rclone remote has a different name

# -----------------------------
# 1. CLEANUP OLD PROCESSES
# -----------------------------
echo "[1/10] Cleaning old processes and Docker containers..."
for p in 5901 6080 4567; do
  if lsof -ti :$p >/dev/null 2>&1; then
    echo "Killing process on port $p"
    lsof -ti :$p | xargs kill -9 || true
  fi
done

docker rm -f suwayomi-server >/dev/null 2>&1 || true

# -----------------------------
# 2. INSTALL DEPENDENCIES
# -----------------------------
echo "[2/10] Installing packages..."
sudo apt update -y
sudo apt install -y wget curl git openbox x11vnc xvfb \
  dbus-x11 fonts-liberation rclone

# -----------------------------
# 3. INSTALL CHROME
# -----------------------------
echo "[3/10] Installing Google Chrome..."
if ! command -v google-chrome >/dev/null 2>&1; then
  wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
  sudo apt update -y
  sudo apt install -y google-chrome-stable
fi

# -----------------------------
# 4. SETUP DOWNLOADS FOLDER
# -----------------------------
echo "[4/10] Setting up Downloads folder..."
mkdir -p "$DOWNLOADS_DIR"

# -----------------------------
# 5. SETUP RCLONE (assumes pre-configured remote)
# -----------------------------
echo "[5/10] Checking rclone remote..."
if ! rclone listremotes | grep -q "^$RCLONE_REMOTE:$"; then
  echo "Rclone remote '$RCLONE_REMOTE' not found. Please run 'rclone config' first."
  exit 1
fi

# -----------------------------
# 6. START GUI (Xvfb + Openbox)
# -----------------------------
echo "[6/10] Starting X11 virtual display..."
export DISPLAY=:1
Xvfb :1 -screen 0 1280x800x16 > /dev/null 2>&1 &
sleep 2

echo "[7/10] Starting Openbox window manager..."
openbox > /dev/null 2>&1 &

# -----------------------------
# 7. START CHROME GUI
# -----------------------------
echo "[8/10] Launching Chrome..."
google-chrome \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --user-data-dir=/tmp/chrome \
  --display=:1 \
  "http://localhost:4567" \
  > /dev/null 2>&1 &

# -----------------------------
# 8. RUN SUWAYOMI DOCKER
# -----------------------------
echo "[9/10] Pulling and running Suwayomi Docker container..."
docker pull ghcr.io/suwayomi/suwayomi-server:latest

docker run -d \
  --name suwayomi-server \
  --network host \
  -v "$DOWNLOADS_DIR":/home/suwayomi/Downloads \
  ghcr.io/suwayomi/suwayomi-server:latest

# -----------------------------
# 9. AUTO-UPLOAD DOWNLOADS TO GDRIVE
# -----------------------------
echo "[10/10] Setting up auto-upload of Downloads to GDrive..."
rclone mount "$RCLONE_REMOTE": "$HOME/$RCLONE_REMOTE" --daemon

# Watch Downloads folder and move to GDrive automatically
if ! command -v inotifywait >/dev/null 2>&1; then
  sudo apt install -y inotify-tools
fi

(
  while true; do
    inotifywait -e close_write,moved_to,create "$DOWNLOADS_DIR" --exclude '.*\.crdownload' >/dev/null 2>&1
    for f in "$DOWNLOADS_DIR"/*; do
      [ -e "$f" ] || continue
      echo "Uploading $f to $RCLONE_REMOTE..."
      rclone move "$f" "$RCLONE_REMOTE:Suwayomi" --progress
    done
  done
) &

echo ""
echo "=============================="
echo " SETUP COMPLETE"
echo "=============================="
echo "Open your Codespace browser → PORT 4567 to access Suwayomi GUI"
echo "All downloads in Chrome will be auto-uploaded to Google Drive."
