#!/bin/bash
set -euo pipefail

# See skript paigaldab MySQL (või MariaDB fallback'ina) vähese väljundiga.

# Kontroll, kas skript käivitatakse rootina
if [ "$EUID" -ne 0 ]; then
    echo "Viga! See skript tuleb käivitada kõrgendatud õigustes."
    echo "Käivita skript, kasutades: sudo $0"
    exit 1
fi

is_mysql_installed() {
    dpkg-query -W -f='${Status}\n' mysql-server 2>/dev/null | grep -q "install ok installed"
}

is_mariadb_installed() {
    dpkg-query -W -f='${Status}\n' mariadb-server 2>/dev/null | grep -q "install ok installed"
}

is_installed() {
    is_mysql_installed || is_mariadb_installed
}

enable_and_start_service() {
    # Pärast paigaldust proovi esmalt mysql teenust, siis mariadb
    if systemctl list-unit-files | grep -q '^mysql\.service'; then
        systemctl enable --now mysql >/dev/null
        SERVICE="mysql"
    elif systemctl list-unit-files | grep -q '^mariadb\.service'; then
        systemctl enable --now mariadb >/dev/null
        SERVICE="mariadb"
    else
        # Viimane katse: proovi mõlemat
        systemctl enable --now mysql >/dev/null 2>/dev/null || true
        systemctl enable --now mariadb >/dev/null 2>/dev/null || true
        if systemctl is-active --quiet mysql; then SERVICE="mysql"
        elif systemctl is-active --quiet mariadb; then SERVICE="mariadb"
        else SERVICE="(tundmatu)"; fi
    fi
}

is_running() {
    systemctl is-active --quiet mysql || systemctl is-active --quiet mariadb
}

if is_installed; then
    echo "MySQL/MariaDB on juba paigaldatud."
else
    echo -n "MySQL puudub. Kas paigaldan? (y - jah, n - ei): "
    read -r yesno
    while true; do
        case "$yesno" in
            [Yy])
                echo "Paigaldan MySQL'i..."
                export DEBIAN_FRONTEND=noninteractive
                apt-get update -y -qq >/dev/null

                # Proovi esmalt Oracle MySQL'i; kui see puudub, paigalda MariaDB
                if ! apt-get install -y -qq mysql-server >/dev/null 2>/dev/null; then
                    echo "MySQL pakett ei ole saadaval. Paigaldan MariaDB..."
                    apt-get install -y -qq mariadb-server >/dev/null
                fi

                if is_installed; then
                    echo "Paigaldus õnnestus. Käivitan ja luban teenuse..."
                    enable_and_start_service

                    if is_running; then
                        echo "MySQL/MariaDB töötab (teenus: ${SERVICE})."
                        exit 0
                    else
                        echo "Hoiatus: teenus ei tööta pärast paigaldust."
                        echo "Kontrolli logisid: journalctl -u mysql -u mariadb --no-pager"
                        exit 1
                    fi
                else
                    echo "Paigaldamine ebaõnnestus."
                    exit 1
                fi
                ;;
            [Nn])
                echo "Paigaldamine tühistatud."
                exit 0
                ;;
            *)
                echo -n "Palun sisesta ainult 'y' või 'n': "
                read -r yesno
                ;;
        esac
    done
fi

# Kui juba paigaldatud, kuva staatus
if is_running; then
    # Püüa teenuse nimi tuvastada
    if systemctl is-active --quiet mysql; then SERVICE="mysql"
    elif systemctl is-active --quiet mariadb; then SERVICE="mariadb"
    else SERVICE="(tundmatu)"; fi
    echo "MySQL/MariaDB juba töötab (teenus: ${SERVICE})."
else
    echo "MySQL/MariaDB on paigaldatud, kuid ei tööta."
    echo "Käivita käsuga: sudo systemctl start mysql   # või: sudo systemctl start mariadb"
fi
