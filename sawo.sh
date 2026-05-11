#!/usr/bin/env bash
set -euo pipefail

# ====================================================
# SUWAYOMI + GUI + AUTO-UPLOAD TO GDRIVE
# With proper series name extraction
# ====================================================

# -----------------------------
# CONFIGURATION
# -----------------------------
DOWNLOADS_DIR="$HOME/Downloads"
RCLONE_REMOTE="gdrive"
GDRIVE_BASE="Suwayomi"
LOG_FILE="$HOME/suwayomi_auto.log"
UPLOADED_FILES="/tmp/uploaded_files.txt"
PROCESSING_FILE="/tmp/processing.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

# Track uploaded files to prevent duplicates
uploaded() {
    grep -qxF "$1" "$UPLOADED_FILES" 2>/dev/null
}

mark_uploaded() {
    echo "$1" >> "$UPLOADED_FILES"
}

# Extract ACTUAL series name from path (not the website folder)
get_series_name() {
    local path="$1"
    
    # Pattern: mangas/WebsiteName (ALL)/Actual Series Name [Author]/ChapterXX.cbz
    # Example: mangas/AllPornComics.co (ALL)/The Hole is Open [Kimtuk]/Chapter 01.cbz
    
    # First, try to extract the series folder (the one with [Author] or just the name)
    if [[ "$path" =~ /mangas/[^/]+/([^/]+)/ ]]; then
        local series="${BASH_REMATCH[1]}"
        
        # Remove [Author] and any brackets
        series=$(echo "$series" | sed 's/\s*\[[^]]*\]//g')
        # Remove trailing/leading spaces
        series=$(echo "$series" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ -n "$series" ] && [ "$series" != " " ] && [ ${#series} -gt 2 ]; then
            echo "$series"
            return
        fi
    fi
    
    # Fallback: try to get series name from the folder structure differently
    if [[ "$path" =~ /mangas/[^/]+/([^/]+) ]]; then
        local series="${BASH_REMATCH[1]}"
        series=$(echo "$series" | sed 's/\s*\[[^]]*\]//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$series" ]; then
            echo "$series"
            return
        fi
    fi
    
    # If all else fails, use the parent folder name
    echo "Misc"
}

# Alternative: Extract from filename if it contains series info
get_series_from_filename() {
    local filename="$1"
    # Remove chapter number and extension
    local name=$(echo "$filename" | sed 's/Chapter\s*[0-9]\+\.cbz//i' | sed 's/\.cbz$//' | sed 's/[[:space:]]*$//')
    if [ -n "$name" ] && [ ${#name} -gt 3 ]; then
        echo "$name"
    else
        echo ""
    fi
}

# -----------------------------
# SETUP RCLONE
# -----------------------------
setup_rclone() {
    log "Setting up rclone configuration..."
    
    mkdir -p "$HOME/.config/rclone"
    
    if [ -f "$HOME/.config/rclone/rclone.conf" ]; then
        if rclone listremotes 2>/dev/null | grep -q "^$RCLONE_REMOTE:"; then
            log "✓ Existing rclone config found"
            return 0
        fi
    fi
    
    for possible_config in \
        "$HOME/workspaces/browser1/rclone.conf" \
        "$HOME/workspaces/browser1/browser/rclone.conf" \
        "$PWD/rclone.conf"
    do
        if [ -f "$possible_config" ]; then
            log "✓ Found config at: $possible_config"
            cp "$possible_config" "$HOME/.config/rclone/rclone.conf"
            break
        fi
    done
    
    if ! rclone listremotes 2>/dev/null | grep -q "^$RCLONE_REMOTE:"; then
        error "No valid rclone config found. Run 'rclone config' first."
        exit 1
    fi
    
    rclone mkdir "$RCLONE_REMOTE:$GDRIVE_BASE" 2>/dev/null || true
    log "✓ Google Drive ready"
}

# -----------------------------
# CLEANUP
# -----------------------------
cleanup() {
    log "Cleaning old processes..."
    for p in 5901 6080 4567; do
        lsof -ti :$p 2>/dev/null | xargs kill -9 2>/dev/null || true
    done
    docker rm -f suwayomi-server 2>/dev/null || true
    > "$UPLOADED_FILES" 2>/dev/null || true
    > "$PROCESSING_FILE" 2>/dev/null || true
}

# -----------------------------
# INSTALL DEPS
# -----------------------------
install_deps() {
    log "Installing dependencies..."
    sudo apt update -y
    sudo apt install -y wget curl git openbox x11vnc xvfb dbus-x11 fonts-liberation inotify-tools docker.io > /dev/null 2>&1
    
    if ! command -v rclone >/dev/null 2>&1; then
        curl https://rclone.org/install.sh | sudo bash > /dev/null 2>&1
    fi
    
    if ! command -v google-chrome >/dev/null 2>&1; then
        wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
        sudo apt update -y
        sudo apt install -y google-chrome-stable > /dev/null 2>&1
    fi
    log "✓ Dependencies installed"
}

# -----------------------------
# START GUI
# -----------------------------
start_gui() {
    log "Starting GUI..."
    export DISPLAY=:1
    Xvfb :1 -screen 0 1280x800x16 > /dev/null 2>&1 &
    sleep 2
    openbox > /dev/null 2>&1 &
    x11vnc -display :1 -nopw -forever -shared -rfbport 5901 > /dev/null 2>&1 &
    websockify --web=/usr/share/novnc 6080 localhost:5901 > /dev/null 2>&1 &
    log "✓ GUI ready (noVNC on 6080)"
}

# -----------------------------
# START CHROME
# -----------------------------
start_chrome() {
    log "Starting Chrome..."
    google-chrome --no-sandbox --disable-dev-shm-usage --disable-gpu \
        --user-data-dir="$HOME/.chrome-suwayomi" --display=:1 \
        --window-size=1280,800 "http://localhost:4567" > /dev/null 2>&1 &
    log "✓ Chrome launched"
}

# -----------------------------
# START SUWAYOMI
# -----------------------------
start_suwayomi() {
    log "Starting Suwayomi..."
    docker pull ghcr.io/suwayomi/suwayomi-server:latest > /dev/null 2>&1
    docker run -d --name suwayomi-server --restart unless-stopped --network host \
        -v suwayomi-data:/home/suwayomi/.local/share/Tachidesk \
        -v "$DOWNLOADS_DIR":/home/suwayomi/.local/share/Tachidesk/downloads \
        ghcr.io/suwayomi/suwayomi-server:latest > /dev/null 2>&1
    log "✓ Suwayomi running on port 4567"
}

# -----------------------------
# AUTO-UPLOAD WITH PROPER NAMING
# -----------------------------
start_watcher() {
    log "Starting auto-upload with proper series naming..."
    
    (
        while true; do
            inotifywait -m -r -e close_write --format '%w%f' "$DOWNLOADS_DIR" 2>/dev/null | while read FULL_PATH; do
                # Skip if not a cbz/zip file
                if [[ ! "$FULL_PATH" =~ \.(cbz|zip)$ ]]; then
                    continue
                fi
                
                # Skip if already uploaded or processing
                if uploaded "$FULL_PATH" || grep -qxF "$FULL_PATH" "$PROCESSING_FILE" 2>/dev/null; then
                    continue
                fi
                
                # Mark as processing
                echo "$FULL_PATH" >> "$PROCESSING_FILE"
                
                # Wait for file to be fully written
                sleep 3
                
                # Verify file still exists
                if [ ! -f "$FULL_PATH" ] || uploaded "$FULL_PATH"; then
                    sed -i "\|$FULL_PATH|d" "$PROCESSING_FILE"
                    continue
                fi
                
                # Get the correct series name
                SERIES=$(get_series_name "$FULL_PATH")
                
                # Fallback to filename if series extraction gave website name
                if [[ "$SERIES" == "AllPornComics.co" ]] || [[ "$SERIES" == *".co"* ]] || [[ ${#SERIES} -lt 3 ]]; then
                    # Try to extract from the path differently
                    if [[ "$FULL_PATH" =~ /mangas/[^/]+/([^/]+)/ ]]; then
                        SERIES="${BASH_REMATCH[1]}"
                        # Remove anything in brackets
                        SERIES=$(echo "$SERIES" | sed 's/\s*\[[^]]*\]//g')
                        SERIES=$(echo "$SERIES" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    fi
                fi
                
                # Final fallback
                if [ -z "$SERIES" ] || [ "$SERIES" = " " ] || [ ${#SERIES} -lt 2 ]; then
                    SERIES="Misc"
                fi
                
                DEST_DIR="$RCLONE_REMOTE:$GDRIVE_BASE/$SERIES"
                REL_PATH="${FULL_PATH#$DOWNLOADS_DIR/}"
                
                log "📚 Series: $SERIES"
                log "📁 File: $(basename "$FULL_PATH")"
                
                # Create series folder in Google Drive
                rclone mkdir "$DEST_DIR" 2>/dev/null || true
                
                # Upload to organized folder with retry
                UPLOAD_SUCCESS=false
                for i in {1..3}; do
                    if rclone move "$FULL_PATH" "$DEST_DIR/" --quiet 2>/dev/null; then
                        mark_uploaded "$FULL_PATH"
                        log "✓ Uploaded to: $GDRIVE_BASE/$SERIES/$(basename "$FULL_PATH")"
                        UPLOAD_SUCCESS=true
                        break
                    else
                        if [ $i -lt 3 ]; then
                            warn "Retry $i/3 for: $(basename "$FULL_PATH")"
                            sleep 2
                        fi
                    fi
                done
                
                if [ "$UPLOAD_SUCCESS" = false ]; then
                    warn "Failed to upload: $(basename "$FULL_PATH") after 3 attempts"
                fi
                
                # Remove from processing
                sed -i "\|$FULL_PATH|d" "$PROCESSING_FILE"
            done
        done
    ) &
}

# -----------------------------
# MANUAL UPLOAD EXISTING FILES WITH CORRECT NAMING
# -----------------------------
upload_existing() {
    log "Checking for existing files to organize with proper naming..."
    
    find "$DOWNLOADS_DIR/mangas" -type f \( -name "*.cbz" -o -name "*.zip" \) 2>/dev/null | while read FILE; do
        if [ -f "$FILE" ] && ! uploaded "$FILE"; then
            # Get proper series name
            SERIES=$(get_series_name "$FILE")
            
            # Fallback if needed
            if [[ "$SERIES" == "AllPornComics.co" ]] || [[ "$SERIES" == *".co"* ]] || [[ ${#SERIES} -lt 3 ]]; then
                if [[ "$FILE" =~ /mangas/[^/]+/([^/]+)/ ]]; then
                    SERIES="${BASH_REMATCH[1]}"
                    SERIES=$(echo "$SERIES" | sed 's/\s*\[[^]]*\]//g')
                    SERIES=$(echo "$SERIES" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                fi
            fi
            
            if [ -z "$SERIES" ] || [ ${#SERIES} -lt 2 ]; then
                SERIES="Misc"
            fi
            
            DEST_DIR="$RCLONE_REMOTE:$GDRIVE_BASE/$SERIES"
            
            log "📚 Organizing: $(basename "$FILE") -> $SERIES"
            rclone mkdir "$DEST_DIR" 2>/dev/null || true
            
            if rclone move "$FILE" "$DEST_DIR/" --quiet 2>/dev/null; then
                mark_uploaded "$FILE"
                log "✓ Organized: $SERIES/$(basename "$FILE")"
            fi
        fi
    done
}

# -----------------------------
# MAIN
# -----------------------------
main() {
    echo ""
    log "=== Suwayomi + Organized GDrive Upload (Fixed Naming) ==="
    echo "=============================="
    
    cleanup
    install_deps
    setup_rclone
    mkdir -p "$DOWNLOADS_DIR"
    touch "$UPLOADED_FILES"
    touch "$PROCESSING_FILE"
    
    start_gui
    start_suwayomi
    sleep 5
    start_chrome
    start_watcher
    
    # Upload existing files after a delay
    sleep 10
    upload_existing &
    
    echo ""
    echo "=============================="
    echo "✓ SETUP COMPLETE"
    echo "=============================="
    echo ""
    echo "📁 ORGANIZATION RULES:"
    echo "   • Extracts series name from the folder containing [Author]"
    echo "   • Ignores website folder names like 'AllPornComics.co'"
    echo "   • Files go to: Suwayomi/Actual Series Name/"
    echo ""
    echo "📍 ACCESS:"
    echo "   • Suwayomi GUI: Port 4567"
    echo "   • noVNC: Port 6080"
    echo ""
    echo "Example structure:"
    echo "   drive:Suwayomi/"
    echo "   ├── The Hole is Open/"
    echo "   │   ├── Chapter 01.cbz"
    echo "   │   └── Chapter 02.cbz"
    echo "   └── Other Series/"
    echo ""
    
    wait
}

main