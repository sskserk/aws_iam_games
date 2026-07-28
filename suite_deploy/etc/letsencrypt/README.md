## Let's Encrypt Certificate Automation

## Foreword

This guide was written for operators who want certificate management to be predictable, and low-maintenance. The goal is not just to obtain a certificate once, but to keep TLS healthy over time without relying on manual reminders.

The two scripts in this folder reflect that approach. One handles the first-time issuance path, and the other performs routine checks so renewals happen before expiry and updated files are rotated into the running stack. Together, they provide a simple operational baseline that can be adopted quickly and audited easily.

If you are onboarding this into a new environment, use this document as an execution playbook first, then as a reference during maintenance windows and post-incident reviews.

This folder contains two scripts that work together:

- `cert_issue.sh` for first-time certificate issuance.
- `cert_daily_check.sh` for ongoing renewal checks and certificate refresh.

The overall idea is simple: issue once, then let the daily check renew and rotate cert files automatically before expiry.

## Script 1: `cert_issue.sh` (Initial certificate setup)

Use this script when a certificate does not exist yet for your domain.

### What it does

1. Sets the target domain and email used by Let's Encrypt.
2. Checks whether host port `80` is already occupied.
3. If needed, stops the configured container (`reverse-proxy`) so Certbot can bind to port `80` for the HTTP-01 challenge.
4. Requests a certificate using `certbot certonly --standalone`.
5. Copies the generated cert and key into:
	- `/opt/awide/eco/nginx/ssl/certificate.pem`
	- `/opt/awide/eco/nginx/ssl/key.pem`
6. Restarts the stopped container on script exit (via `trap`).

### Configurable values

Edit these variables at the top of the script:

- `DOMAIN`
- `EMAIL`
- `PORT80_CONTAINER`
- `CONTAINER_RUNTIME`
- `CONTAINER_USER`

### Run command

```bash
sudo bash /path/to/cert_issue.sh
```

## Script 2: `cert_daily_check.sh` (Renewal and rotation)

Use this script as a scheduled job (cron). It checks certificate lifetime and renews only when needed.

### What it does

1. Reads certificate files from `/etc/letsencrypt/live/<domain>/`.
2. Checks if the certificate expires within `RENEW_BEFORE_DAYS` (default: 7).
3. If renewal is needed:
	- Stops the container using host port `80`.
	- Runs `certbot renew --non-interactive`.
	- Copies refreshed cert/key to `/opt/awide/eco/nginx/ssl/`.
	- Restarts the TLS container.
4. If renewal is not needed, exits cleanly.
5. Logs all actions to `/var/log/awide_cert.log`.

### Configurable values

Edit these variables at the top of the script:

- `DOMAIN`
- `PORT80_CONTAINER`
- `TARGET_CERT_DIR`
- `RENEW_BEFORE_DAYS`
- `CONTAINER_RUNTIME`
- `CONTAINER_USER`

### Manual test run

```bash
sudo bash /path/to/cert_daily_check.sh
```

## Scheduling with cron

Run `cert_setup.sh` once to install Certbot and `cronie`, and enable `crond`:

```bash
sudo bash /path/to/cert_setup.sh
```

After that, register the daily renewal check as root:

```bash
sudo crontab -e
```

Add a daily run (example: 03:20 UTC):

```cron
20 3 * * * /usr/bin/bash /path/to/cert_daily_check.sh
```

Tip: start with a manual run first to confirm paths, domain DNS, and container name are correct.

## Operational notes

- Ensure DNS for `DOMAIN` points to this host.
- Ensure inbound `80/tcp` and `443/tcp` are allowed at the network/security-group layer.
- The scripts assume the TLS endpoint serves cert files from `/opt/awide/eco/nginx/ssl`.
- Both scripts rely on sudo and container runtime access for the configured user.

## Troubleshooting quick checks

- Challenge fails: verify domain DNS and external access to port `80`.
- Port conflict errors: confirm `PORT80_CONTAINER` is the correct container name.
- No cert updates in proxy: confirm file copy destination and container restart behavior.
- Review logs in `/var/log/awide_cert.log` for execution history.
