#!/usr/bin/env bash
# apache_paigaldus.sh — kontrollib, paigaldab (kui vaja) ja näitab apache2 staatust
# Mõeldud Debiani/Ubuntu-põhistele süsteemidele.

set -euo pipefail

PKG="apache2"
SERVICE="apache2"

echo ">>> Kontrollin, kas $PKG on paigaldatud ..."

# loe dpkg-query väljund; kui paketti pole, ära kuku läbi
dpkg_status="$(dpkg-query -W -f='${Status}' "$PKG" 2>/dev/null || true)"

if echo "$dpkg_status" | grep -q "ok installed"; then
  echo "OK: $PKG on juba paigaldatud."
else
  echo "PAIGALDAN: $PKG ei ole paigaldatud. Alustan paigaldust..."
  sudo apt-get update -y
  sudo apt-get install -y "$PKG"
  echo "Valmis: $PKG on paigaldatud."
fi

echo
echo ">>> Käivitan teenuse (kui veel ei tööta) ja näitan staatust."

# proovi systemctl'i; kui service-fail puudub, kasuta legacy 'service'
if systemctl list-unit-files | grep -q "^${SERVICE}\.service"; then
  sudo systemctl enable --now "$SERVICE" >/dev/null 2>&1 || true
  echo
  sudo systemctl --no-pager --full status "$SERVICE" || true
else
  sudo service "$SERVICE" start || true
  echo
  sudo service "$SERVICE" status || true
fi

echo
echo ">>> Tööd tehtud."
