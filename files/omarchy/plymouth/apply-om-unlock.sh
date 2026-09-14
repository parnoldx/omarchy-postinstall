#!/bin/bash
set -euo pipefail

LOGO="$HOME/.config/omarchy/plymouth/om-unlock.png"
STATUS="$HOME/.config/omarchy/plymouth/apply-status"

echo "running" >"$STATUS"

echo "Setting the disk-encryption unlock screen to the Om logo."
echo "This needs sudo and will rebuild the initramfs (can take a minute)."
echo

if omarchy plymouth set '#000000' '#ffffff' "$LOGO"; then
  echo ok >"$STATUS"
  echo
  echo "Unlock screen updated. It will show on the next reboot."
else
  echo "fail:$?" >"$STATUS"
  echo
  echo "That failed. Close this window and try again."
  exit 1
fi
