while true; do
  curl -s http://localhost:6080 >/dev/null
  sleep 300
done &