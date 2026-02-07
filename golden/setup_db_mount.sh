#!/bin/bash

# Idempotent disk setup script:
# - Ensures DEVICE has an ext4 filesystem (creates it only when needed).
# - Ensures MOUNT_POINT has a stable /etc/fstab entry by UUID.
# - Ensures the filesystem is mounted on MOUNT_POINT.
#
# Usage:
#   sudo ./setup_disk.sh [--dry-run] [--force]
#
# Flags:
#   --dry-run  Print actions without changing the system.
#   --force    Allow destructive mkfs when an existing filesystem is not ext4.

set -euo pipefail

DEVICE="/dev/sda1"
MOUNT_POINT="/var/lib/awidedbdata"

DRY_RUN=false
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force)   FORCE=true ;;
    *)
      echo "Error: Unknown argument: $arg" >&2
      echo "Usage: sudo $0 [--dry-run] [--force]" >&2
      exit 1
      ;;
  esac
done

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] $*"
  else
    "$@"
  fi
}

backup_file_once() {
  local src="$1"
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  run cp "$src" "${src}.backup.${ts}"
  echo "Backup created: ${src}.backup.${ts}"
}

is_mountpoint() {
  # True only if PATH is an actual mount point.
  local p="$1"
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$p"
  else
    # Fallback: compare the nearest mount target with the path itself.
    local t
    t=$(findmnt -n -o TARGET --target "$p" 2>/dev/null || true)
    [[ "$t" == "$p" ]]
  fi
}

if [[ "$DRY_RUN" == true ]]; then
  echo "*** DRY RUN MODE - No changes will be made ***"
  echo ""
fi

if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == false ]]; then
  echo "Error: This script must be run as root (use sudo)" >&2
  exit 1
fi

echo "=== Disk Setup Script (Idempotent) ==="
echo "Device: $DEVICE"
echo "Mount Point: $MOUNT_POINT"
echo "Dry-run: $DRY_RUN"
echo "Force: $FORCE"
echo ""

echo "Step 1: Resolving device name..."
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] readlink -f $DEVICE"
  REAL_DEVICE="$DEVICE"
else
  REAL_DEVICE=$(readlink -f "$DEVICE")
fi
echo "Real device: $REAL_DEVICE"
echo ""

echo "Step 2: Ensuring mount point directory exists..."
run mkdir -p "$MOUNT_POINT"
echo "Mount point directory ready: $MOUNT_POINT"
echo ""

# Step 3: Check whether MOUNT_POINT is a real mount point.
# Important: findmnt --target shows the backing filesystem even if there is no dedicated mount.
# Therefore we must use mountpoint semantics here.
echo "Step 3: Checking whether $MOUNT_POINT is already a mount point..."
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] mountpoint -q $MOUNT_POINT"
  echo "[DRY RUN] If it is a mount point, would compare mounted UUID with device UUID."
  echo ""
else
  if is_mountpoint "$MOUNT_POINT"; then
    MOUNTED_UUID=$(findmnt -n -o UUID --target "$MOUNT_POINT" 2>/dev/null || true)
    MOUNTED_SRC=$(findmnt -n -o SOURCE --target "$MOUNT_POINT" 2>/dev/null || true)
    echo "Already mounted: source=$MOUNTED_SRC uuid=$MOUNTED_UUID"

    DEVICE_UUID=$(blkid -s UUID -o value "$REAL_DEVICE" 2>/dev/null || true)

    if [[ -n "$DEVICE_UUID" && -n "$MOUNTED_UUID" && "$DEVICE_UUID" == "$MOUNTED_UUID" ]]; then
      echo "Mount point is already mounted with the expected UUID. No remount needed."
    else
      echo "Error: $MOUNT_POINT is mounted from a different filesystem." >&2
      echo "Mounted: source=$MOUNTED_SRC uuid=$MOUNTED_UUID" >&2
      echo "Target device: $REAL_DEVICE uuid=${DEVICE_UUID:-<none>}" >&2
      echo "Refusing to modify /etc/fstab or remount." >&2
      exit 1
    fi
  else
    echo "Not a mount point yet."
  fi
  echo ""
fi

echo "Step 4: Detecting filesystem type on $REAL_DEVICE..."
FS_TYPE=""
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] blkid -o value -s TYPE $REAL_DEVICE"
  FS_TYPE=""
  echo "Filesystem type (simulated): <none>"
else
  FS_TYPE=$(blkid -o value -s TYPE "$REAL_DEVICE" 2>/dev/null || true)
  echo "Filesystem type: ${FS_TYPE:-<none>}"
fi
echo ""

echo "Step 5: Ensuring ext4 filesystem..."
if [[ -z "$FS_TYPE" ]]; then
  echo "No filesystem detected. Creating ext4 on $REAL_DEVICE."
  run mkfs.ext4 -F "$REAL_DEVICE"
  echo "ext4 filesystem created."
elif [[ "$FS_TYPE" == "ext4" ]]; then
  echo "ext4 filesystem already present. Skipping mkfs."
else
  echo "Existing filesystem is '$FS_TYPE' (not ext4)."
  if [[ "$FORCE" == true ]]; then
    echo "--force provided. Recreating filesystem as ext4 (DESTRUCTIVE)."
    run mkfs.ext4 -F "$REAL_DEVICE"
    echo "ext4 filesystem created."
  else
    echo "Error: Refusing to format. Re-run with --force to overwrite '$FS_TYPE' with ext4." >&2
    exit 1
  fi
fi
echo ""

echo "Step 6: Getting UUID for $REAL_DEVICE..."
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] blkid -s UUID -o value $REAL_DEVICE"
  UUID="12345678-1234-1234-1234-123456789abc"
  echo "UUID (simulated): $UUID"
else
  sleep 1
  UUID=$(blkid -s UUID -o value "$REAL_DEVICE" 2>/dev/null || true)
  if [[ -z "$UUID" ]]; then
    echo "Error: Could not retrieve UUID for $REAL_DEVICE" >&2
    exit 1
  fi
  echo "UUID: $UUID"
fi
echo ""

echo "Step 7: Ensuring persistent mount in /etc/fstab..."
FSTAB_FILE="/etc/fstab"
FSTAB_ENTRY="UUID=$UUID $MOUNT_POINT ext4 defaults 0 2"

if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] Ensure fstab has: $FSTAB_ENTRY"
else
  if awk -v mp="$MOUNT_POINT" '($1 !~ /^#/ && $2 == mp) {found=1} END{exit found?0:1}' "$FSTAB_FILE"; then
    CURRENT_LINE=$(awk -v mp="$MOUNT_POINT" '($1 !~ /^#/ && $2 == mp) {print; exit}' "$FSTAB_FILE")
    if [[ "$CURRENT_LINE" == "$FSTAB_ENTRY" ]]; then
      echo "fstab entry already correct. Skipping modification."
    else
      backup_file_once "$FSTAB_FILE"
      awk -v mp="$MOUNT_POINT" -v repl="$FSTAB_ENTRY" '
        {
          if ($0 ~ /^#/) { print $0; next }
          if ($2 == mp) { print repl; next }
          print $0
        }' "$FSTAB_FILE" > "${FSTAB_FILE}.tmp"
      mv "${FSTAB_FILE}.tmp" "$FSTAB_FILE"
      echo "Updated fstab entry for: $MOUNT_POINT"
    fi
  else
    backup_file_once "$FSTAB_FILE"
    echo "$FSTAB_ENTRY" >> "$FSTAB_FILE"
    echo "Added fstab entry: $FSTAB_ENTRY"
  fi
fi
echo ""

echo "Step 8: Ensuring the filesystem is mounted on $MOUNT_POINT..."
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] If not a mount point, would run: mount $MOUNT_POINT"
else
  if is_mountpoint "$MOUNT_POINT"; then
    echo "Already mounted. Nothing to do."
  else
    # Prefer mounting via fstab.
    mount "$MOUNT_POINT" 2>/dev/null || mount "$REAL_DEVICE" "$MOUNT_POINT"
    echo "Mounted: $REAL_DEVICE -> $MOUNT_POINT"
  fi
fi
echo ""

echo "=== Verification ==="
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] df -h $MOUNT_POINT"
  echo "[DRY RUN] grep -n -- \" $MOUNT_POINT \" /etc/fstab"
else
  df -h "$MOUNT_POINT" || true
  echo ""
  grep -n -- " $MOUNT_POINT " /etc/fstab || true
fi
echo ""
echo "=== Setup Complete ==="
