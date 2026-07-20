#!/usr/bin/env bash
set -euo pipefail

###############################################
# CONFIGURATION
###############################################
DOMAIN="dev.awide.tech"

# Container currently using host port 80
PORT80_CONTAINER="reverse-proxy"
CONTAINER_RUNTIME="docker"
CONTAINER_USER="root"


# Where to copy cert/key for your proxy
TARGET_CERT_DIR="/opt/awide/eco/nginx/ssl"

# Renewal threshold (days)
RENEW_BEFORE_DAYS=7

# Append all output to this file.
LOG_FILE="/var/log/awide_cert.log"

###############################################
# INTERNALS
###############################################
SECONDS_THRESHOLD=$((RENEW_BEFORE_DAYS * 24 * 3600))
LIVE_DIR="/etc/letsencrypt/live/${DOMAIN}"
FULLCHAIN="${LIVE_DIR}/fullchain.pem"
PRIVKEY="${LIVE_DIR}/privkey.pem"

log() {
	echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

mkdir -p "$(dirname "$LOG_FILE")"
exec >> "$LOG_FILE" 2>&1

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "Missing required command: $1" >&2
		exit 1
	}
}

need_cmd sudo
need_cmd "$CONTAINER_RUNTIME"
need_cmd certbot
need_cmd openssl

ctr() {
	sudo -iu "$CONTAINER_USER" "$CONTAINER_RUNTIME" "$@"
}

container_running() {
	local c="$1"
	[[ "$(ctr inspect -f '{{.State.Running}}' "$c" 2>/dev/null || true)" == "true" ]]
}

stop_container_if_running() {
	local c="$1"
	if container_running "$c"; then
		log "Stopping container: $c"
		ctr stop "$c" >/dev/null
		return 0
	fi
	return 1
}

start_container() {
	local c="$1"
	log "Starting container: $c"
	ctr start "$c" >/dev/null
}

copy_certs() {
	mkdir -p "$TARGET_CERT_DIR"
	cp "$FULLCHAIN" "$TARGET_CERT_DIR/certificate.pem"
	cp "$PRIVKEY" "$TARGET_CERT_DIR/key.pem"
	log "Certificates copied to $TARGET_CERT_DIR"
}

should_renew=true

if [[ ! -f "$FULLCHAIN" || ! -f "$PRIVKEY" ]]; then
	log "Certificate files not found. Initial issuance required."
	should_renew=true
else
	if openssl x509 -checkend "$SECONDS_THRESHOLD" -noout -in "$FULLCHAIN"; then
		log "Certificate is valid for more than ${RENEW_BEFORE_DAYS} days. No renewal needed."
		should_renew=false
	else
		log "Certificate expires in less than ${RENEW_BEFORE_DAYS} days. Renewal required."
		should_renew=true
	fi
fi


if [[ "$should_renew" == "false" ]]; then
	log "Skipping copy/restart because renewal is not required."
	exit 0
fi

stopped_port80_container=false
if stop_container_if_running "$PORT80_CONTAINER"; then
	stopped_port80_container=true
fi

cleanup() {
	if [[ "$stopped_port80_container" == "true" ]]; then
		start_container "$PORT80_CONTAINER"
	fi
}
trap cleanup EXIT

log "Requesting/Renewing certificate for domain: $DOMAIN"
certbot renew --non-interactive

copy_certs

if [[ -n "$PORT80_CONTAINER" ]]; then
	log "Restarting TLS container: $PORT80_CONTAINER"
	ctr restart "$PORT80_CONTAINER" >/dev/null
fi

log "Let's Encrypt weekly check completed successfully."