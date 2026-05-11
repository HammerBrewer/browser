#!/usr/bin/env bash

case "$1" in
    stop)
        echo "Stopping Suwayomi and services..."
        docker rm -f suwayomi-server 2>/dev/null
        pkill -f "google-chrome.*suwayomi"
        pkill -f "Xvfb.*:1"
        pkill -f "inotifywait.*Downloads"
        echo "✓ Stopped"
        ;;
    restart)
        $0 stop
        sleep 2
        ./suwayomi-auto.sh
        ;;
    status)
        echo "=== Service Status ==="
        docker ps | grep suwayomi-server && echo "✓ Suwayomi running" || echo "✗ Suwayomi stopped"
        pgrep -f "inotifywait" > /dev/null && echo "✓ Upload watcher running" || echo "✗ Upload watcher stopped"
        echo "=== Google Drive Usage ==="
        rclone about drive: 2>/dev/null || echo "Cannot connect to Google Drive"
        ;;
    logs)
        tail -f ~/suwayomi_auto.log
        ;;
    backup)
        echo "Backing up Suwayomi config..."
        docker run --rm -v suwayomi-data:/data -v $PWD:/backup alpine tar czf /backup/suwayomi-backup-$(date +%Y%m%d).tar.gz -C /data . 
        echo "✓ Backup saved to: suwayomi-backup-$(date +%Y%m%d).tar.gz"
        ;;
    *)
        echo "Usage: $0 {stop|restart|status|logs|backup}"
        exit 1
        ;;
esac