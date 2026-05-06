#!/usr/bin/env bash
set -euo pipefail

echo "=============================="
echo " NO VNC + CHROME (SAFE MODE)"
echo "=============================="

# -----------------------------
# 1. SAFE CLEANUP (PORT BASED ONLY)
# -----------------------------
echo "[1/8] Cleaning ports safely..."

for p in 5901 6080; do
  if lsof -ti :$p >/dev/null 2>&1; then
    echo "Killing process on port $p"
    lsof -ti :$p | xargs kill -9 || true
  fi
done

# -----------------------------
# 2. INSTALL DEPENDENCIES
# -----------------------------
echo "[2/8] Installing packages..."

sudo apt update -y
sudo apt install -y \
  wget curl git \
  openbox x11vnc xvfb \
  novnc websockify \
  dbus-x11 fonts-liberation

# -----------------------------
# 3. INSTALL CHROME
# -----------------------------
echo "[3/8] Installing Chrome..."

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
echo "[4/8] Starting display..."

export DISPLAY=:1
Xvfb :1 -screen 0 1280x800x16 > /dev/null 2>&1 &

sleep 2

# -----------------------------
# 5. START OPENBOX
# -----------------------------
echo "[5/8] Starting window manager..."

openbox > /dev/null 2>&1 &

# -----------------------------
# 6. START VNC
# -----------------------------
echo "[6/8] Starting VNC..."

x11vnc -display :1 -nopw -forever -shared -rfbport 5901 \
  > /dev/null 2>&1 &

# -----------------------------
# 7. START NOVNC
# -----------------------------
echo "[7/8] Starting noVNC..."

websockify --web=/usr/share/novnc 6080 localhost:5901 \
  > /dev/null 2>&1 &

# -----------------------------
# 8. START CHROME
# -----------------------------
echo "[8/8] Launching Chrome..."

google-chrome \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --user-data-dir=/tmp/chrome \
  --display=:1 \
  https://www.google.com \
  > /dev/null 2>&1 &

echo ""
echo "=============================="
echo " READY"
echo "=============================="
echo ""
echo "Open:"
echo "👉 Codespaces → PORT 6080 → Open in Browser"
echo ""