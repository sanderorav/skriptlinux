#!/bin/bash

# See skript paigaldab MySQL ja määrab root kasutajale parooliks qwerty

# Kontroll, kas kasutatakse root või sudo
if [ "$EUID" -ne 0 ]; then
  echo "Viga: Skripti saab kasutada ainult root või sudo õigustes."
  echo "Sisesta: sudo $0"
  exit 1
fi

echo "Käivitan skripti..."

echo "Laadin MySQL paketi..."
wget https://dev.mysql.com/get/mysql-apt-config_0.8.36-1_all.deb
dpkg -i mysql-apt-config_0.8.36-1_all.deb

echo "Paigaldan gnupg..."
apt install gnupg -y

echo "Uuendan paketid..."
apt update -y

echo "Paigaldan MySQL serveri..."
DEBIAN_FRONTEND=noninteractive apt install -y mysql-server

echo "Määran MySQL root parooli..."

mysqladmin -u root password 'qwerty' 2>/dev/null

systemctl enable mysql
systemctl start mysql

echo "Kontrollin MySQL paigaldust..."
mysql --version

echo "Katsetan root-na sisselogimist..."
mysql -u root -p'qwerty' -e "SELECT 'MySQL installation successful!' AS Message;"

echo "MySQL paigaldus edukalt lõppenud."
echo "Root parool: qwerty"
echo "Sisselogimiseks sisesta: mysql -u root -p"
