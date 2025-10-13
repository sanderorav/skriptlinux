#!/bin/bash
set -euo pipefail

# See skript on mõeldud Apache paigaldamiseks. Kõigepealt kontrollitakse, kas Apache on juba olemas, ja kui mitte,
# siis paigaldatakse.

# Kontroll, kas skript käivitatakse rootina
if [ "$EUID" -ne 0 ]; then
    echo "Viga! See skript tuleb käivitada kõrgendatud õigustes."
    echo "Käivita skript, kasutades: sudo $0"
    exit 1
fi

# Funktsioon: kontrollib, kas apache2 on installitud
is_installed() {
    dpkg-query -W -f='${Status}' apache2 2>/dev/null | grep -q "install ok installed"
}

# Kontroll, kas Apache on juba paigaldatud
if is_installed; then
    echo "Apache on juba paigaldatud."
else
    echo -n "Apache puudub. Kas paigaldan? (y - jah, n - ei): "
    read -r yesno
    while true; do
        case "$yesno" in
            [Yy])
                echo "Paigaldan Apache..."
		export DEBIAN_FRONTEND=noninteractive
                apt-get update -y -qq >/dev/null
                apt-get install -y -qq apache2 >/dev/null

                if is_installed; then
                    echo "Apache on edukalt paigaldatud. Käivitan ja seadistan teenuse..."
                    # Käivita ja luba automaatne käivitus
                    systemctl enable --now apache2 || true
                    # Kontrolli, kas töötab
                    if systemctl is-active --quiet apache2; then
                        echo "Apache on edukalt käivitatud."
                        exit 0
                    else
                        echo "Hoiatus: Apache ei tööta pärast paigaldust."
                        echo "Vaata logisid käsuga: journalctl -u apache2 --no-pager"
                        exit 1
                    fi
                else
                    echo "Apache paigaldamine ebaõnnestus."
                    exit 1
                fi
                ;;
            [Nn])
                echo "Apache paigaldamine tühistatud."
                exit 0
                ;;
            *)
                echo -n "Palun sisesta ainult 'y' või 'n': "
                read -r yesno
                ;;
        esac
    done
fi

# Kui juba paigaldatud, teavita, kas töötab
if systemctl is-active --quiet apache2; then
    echo "Apache töötab."
else
    echo "Apache on paigaldatud, kuid ei tööta."
    echo "Käivita käsuga: sudo systemctl start apache2"
fi
