#!/usr/bin/env bash
set -euo pipefail

DOMAIN="dev.awide.tech"
PORT80_CONTAINER="reverse-proxy"
EMAIL="admin@awide.tech"
CONTAINER_RUNTIME="docker"
CONTAINER_USER="root"

# Append all output to this file.
LOG_FILE="/var/log/awide_cert.log"

# This script uses the HTTP-01 challenge with certbot's standalone mode.
# Ensure ports 80 and 443 are open and your domain points to this server.

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

ctr() {
	sudo -iu "$CONTAINER_USER" "$CONTAINER_RUNTIME" "$@"
}


# Check if port 80 is in use
if lsof -i :80 -sTCP:LISTEN -t >/dev/null 2>&1; then
	# Port 80 is in use, try to stop the container
	if ctr inspect "$PORT80_CONTAINER" >/dev/null 2>&1; then
		if ctr inspect -f '{{.State.Running}}' "$PORT80_CONTAINER" | grep -q true; then
			ctr stop "$PORT80_CONTAINER"
			trap 'ctr start "$PORT80_CONTAINER"' EXIT
		else
			echo "Error: Port 80 is in use but $PORT80_CONTAINER is not running. Please free port 80 manually." >&2
			exit 1
		fi
	else
		echo "Error: Port 80 is in use but container $PORT80_CONTAINER does not exist. Please free port 80 manually." >&2
		exit 1
	fi
else
	echo "Port 80 is free, proceeding without stopping any container."
fi

certbot certonly \
	--standalone \
	--preferred-challenges http \
	--non-interactive \
	--agree-tos \
	-m "$EMAIL" \
	-d "$DOMAIN"

cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "/opt/awide/eco/nginx/ssl/certificate.pem"
cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "/opt/awide/eco/nginx/ssl/key.pem"       