#!/bin/bash
# Kontrollib PHP olemasolu ja paigaldab kas distro vaikimisi PHP versiooni
# või (VÄLJA-TOETAMATA) PHP 7.0 Sury repositooriumist.
# Kasuta: TARGET_PHP_VERSION=7.0 sudo ./php_paigaldus.sh  # kui vajad just 7.0
# või lihtsalt: sudo ./php_paigaldus.sh                  # soovitatav (paigaldab PHP 8.x)

set -e

# --- root/sudo kontroll ---
if [ "$EUID" -ne 0 ]; then
  echo "See skript peab olema käivitatud root'i või sudo õigustes."
  echo "Palun käivita: sudo $0"
  exit 1
fi

TARGET_PHP_VERSION="${TARGET_PHP_VERSION:-}"

echo "Uuendame paketiloendeid…"
apt-get update -y

# Kas PHP on juba olemas?
if command -v php >/dev/null 2>&1; then
  echo "PHP on juba paigaldatud: $(php -v | head -n1)"
  which php
  exit 0
fi

if [ -z "$TARGET_PHP_VERSION" ]; then
  # Soovitatav: kasuta distro metapakke (installib nt PHP 8.x)
  echo "Paigaldame distro vaikimisi PHP versiooni (php, libapache2-mod-php, php-mysql)…"
  apt-get install -y php libapache2-mod-php php-mysql
else
  if [ "$TARGET_PHP_VERSION" = "7.0" ]; then
    echo "Paigaldad PHP 7.0 (EOL). Vajalik on väline Sury repo."
    # Lisa Sury repo (Ubuntu/Debian)
    apt-get install -y ca-certificates apt-transport-https lsb-release curl gnupg
    curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury.gpg
    echo "deb [signed-by=/usr/share/keyrings/sury.gpg] https://packages.sury.org/php $(lsb_release -sc) main" \
      > /etc/apt/sources.list.d/php-sury.list
    apt-get update -y
    apt-get install -y php7.0 libapache2-mod-php7.0 php7.0-mysql || {
      echo "PHP 7.0 pakette ei õnnestunud paigaldada (distro ${LSB_RELEASE:-unknown})."
      echo "Kontrolli, et Sury repo toetab sinu väljalaset, või kasuta kaasaegset PHP versiooni."
      exit 1
    }
  else
    echo "Toetamata TARGET_PHP_VERSION: $TARGET_PHP_VERSION"
    echo "Jäta muutmata (paigaldab vaikimisi versiooni) või aseta TARGET_PHP_VERSION=7.0"
    exit 1
  fi
fi

echo "Valmis. Paigaldatud PHP: $(php -v | head -n1)"
