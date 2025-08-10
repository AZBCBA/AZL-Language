AZL Production Deployment

Systemd service (containerized)
- Prereqs: Docker installed and azl:prod image built

Build the image:
  docker build -t azl:prod .

Install service:
  sudo mkdir -p /etc/systemd/system
  sudo cp deployment/systemd/azl.service /etc/systemd/system/azl.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now azl.service

Check status/logs:
  systemctl status azl.service
  journalctl -u azl.service -f

Tune runtime:
- Set AZL_ENABLE_QUANTUM=1 in the service file to enable quantum path
- Logs are capped via docker log options (10MB x 5 files)

Local smoke test without systemd:
  docker run --rm azl:prod


