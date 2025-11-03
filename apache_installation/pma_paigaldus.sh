#!/bin/bash

# See skript paigaldab phpmyadmin

# Kontrollime, kas kasutatakse sudo
if [ "$EUID" -ne 0 ]; then
    echo "Viga! See skript tuleb käivitada kõrgendatud õigustes."
    echo "Käivita skript, kasutades: sudo $0"
    exit 1
fi

PMA=$(dpkg-query -W -f='$(Status)' phpmyadmin 2>/dev/null | grep -c 'ok installed')

if [ $PMA -eq 0 ]; then
	echo "Paigaldame phpmyadmin ja vajalikud lisad"
	apt install phpmyadmin
	echo "phpmyadmin on paigaldatud"
elif [ $PMA -eq 1 ]; then
	echo "phpmyadmin on juba paigaldatud"
fi
