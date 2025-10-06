#!/bin/bash
# Automaatne varundusskript: backupexec.sh
# Teeb varukoopia SRC_DIR kaustast, kontrollib ruumi, terviklikkust,
# arvutab ja kontrollib SHA-256, kasutab .backupignore välistusi,
# proovib zstd/gzip/xz ja valib parima (kõige väiksema) arhiivi,
# hoiab alles ainult 3 viimast koopiat, logib ja puhastab ajutised failid.

set -o errexit
set -o nounset
set -o pipefail

# --- Konfiguratsioon ---
SRC_DIR=~/skriptlinux/praks2/src
BACKUP_DIR=~/skriptlinux/praks2/backup
LOG_DIR=~/skriptlinux/praks2/logs
LOG_FILE="$LOG_DIR/backup.log"
IGNORE_FILE="$SRC_DIR/.backupignore"

# Vaikimisi välistused (lisaks .backupignore sisule, kui see olemas)
DEFAULT_EXCLUDES=( --exclude='*.jpg' --exclude='bin' )

# Puhvri protsent vaba ruumi kontrollis (enne pakkimist)
SPACE_BUFFER_PCT=10   # nt 10% puhver
# Mitu komplekti (faili) kokku alles jätta
KEEP_COUNT=3

# --- Eeltöö ---
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

DATE=$(date +%F_%H%M%S)
BASENAME="src-$DATE"
FINAL_PREFIX="$BACKUP_DIR/$BASENAME"  # siia kolitakse valitud arhiiv
TMPROOT=$(mktemp -d)
trap 'rc=$?; rm -rf "$TMPROOT"; exit $rc' EXIT

# Ajutised teed kolmele arhiivile
TMP_ZST="$TMPROOT/$BASENAME.tar.zst"
TMP_GZ="$TMPROOT/$BASENAME.tar.gz"
TMP_XZ="$TMPROOT/$BASENAME.tar.xz"

# Välistusvalik .backupignore jaoks (kui on)
IGNORE_OPT=()
if [ -f "$IGNORE_FILE" ]; then
  IGNORE_OPT=( --exclude-from="$IGNORE_FILE" )
fi

# Kuiv jooks: ainult loend, uut arhiivi ei tehta
if [[ "${1:-}" == "dry" ]]; then
  echo "KUIVJOOKS: näitan, mis failid läheks arhiivi (arhiivi ei looda)."
  tar -cf - "${IGNORE_OPT[@]}" "${DEFAULT_EXCLUDES[@]}" \
      -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")" \
    | tar -tvf -
  echo "Kuiv jooks lõpetatud — uut faili ei loodud."
  exit 0
fi

# --- 1) Vaba ruumi kontroll ---
SRC_BYTES=$(du -sb "$SRC_DIR" | awk '{print $1}')
REQUIRED_BYTES=$(( SRC_BYTES + SRC_BYTES * SPACE_BUFFER_PCT / 100 ))
FREE_BYTES=$(df -B1 "$BACKUP_DIR" | awk 'NR==2{print $4}')

if (( FREE_BYTES < REQUIRED_BYTES )); then
  echo "Viga: vaba ruumi on liiga vähe (vajalik: ${REQUIRED_BYTES} B, vaba: ${FREE_BYTES} B). Varundust ei käivitata."
  printf "[ %s ] BACKUP ABORT (not enough space: need %sB, free %sB)\n" \
    "$(date '+%F %T')" "$REQUIRED_BYTES" "$FREE_BYTES" >> "$LOG_FILE"
  exit 2
fi

# --- 2) Logi algus ---
printf "[ %s ] BACKUP START\n" "$(date '+%F %T')" >> "$LOG_FILE"

# --- 3) Kolm pakkimist (zstd, gzip, xz) ajutises kaustas ---
echo "Pakkimine: zstd, gzip ja xz..."

# zstd
tar -I 'zstd -19 -T0' -cf "$TMP_ZST" "${IGNORE_OPT[@]}" "${DEFAULT_EXCLUDES[@]}" \
  -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")"
# gzip
tar -zcf "$TMP_GZ" "${IGNORE_OPT[@]}" "${DEFAULT_EXCLUDES[@]}" \
  -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")"
# xz
tar -Jcf "$TMP_XZ" "${IGNORE_OPT[@]}" "${DEFAULT_EXCLUDES[@]}" \
  -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")"

# Kontroll, et failid on olemas
for F in "$TMP_ZST" "$TMP_GZ" "$TMP_XZ"; do
  [ -f "$F" ] || { echo "Viga: arhiivi loomine ebaõnnestus: $F"; printf "[ %s ] BACKUP FAILED (create %s)\n" "$(date '+%F %T')" "$F" >> "$LOG_FILE"; exit 1; }
done

# --- 4) Arhiivide avamise kontroll + alamkaustade olemasolu ---
echo "Kontrollin, et arhiivid avanevad ja sisaldavad alamkaustu..."
# ZST: loendamiseks vajame -I 'zstd -d'
tar -I 'zstd -d' -tf "$TMP_ZST" | head -n 5 >/dev/null
tar -tf "$TMP_GZ" | head -n 5 >/dev/null
tar -tf "$TMP_XZ" | head -n 5 >/dev/null

# Alamkaustade kontroll (piisab, kui all on vähemalt üks alamkaust)
check_subdirs() {
  local file="$1" flag="${2:-}"
  if [ -n "$flag" ]; then
    tar -I "$flag" -tf "$file" | grep -qE '^src/.+/$'
  else
    tar -tf "$file" | grep -qE '^src/.+/$'
  fi
}

check_subdirs "$TMP_ZST" 'zstd -d' || echo "Hoiatus: zst arhiivis ei leitud alamkaustu."
check_subdirs "$TMP_GZ"              || echo "Hoiatus: gz arhiivis ei leitud alamkaustu."
check_subdirs "$TMP_XZ"              || echo "Hoiatus: xz arhiivis ei leitud alamkaustu."

# --- 5) SHA-256: arvutus ja -c kontroll kõigile kolmele ---
echo "Arvutan ja kontrollin SHA-256 kontrollsummasid..."
for F in "$TMP_ZST" "$TMP_GZ" "$TMP_XZ"; do
  sha256sum "$F" > "$F.sha256"
  sha256sum -c "$F.sha256"
done

# --- 6) Valime parima kompressori (kõige väiksem fail) ---
SIZE_ZST=$(stat -c '%s' "$TMP_ZST")
SIZE_GZ=$(stat -c '%s' "$TMP_GZ")
SIZE_XZ=$(stat -c '%s' "$TMP_XZ")

CHOSEN_FILE="$TMP_ZST"
CHOSEN_EXT="zst"
CHOSEN_SIZE="$SIZE_ZST"

if (( SIZE_GZ < CHOSEN_SIZE )); then
  CHOSEN_FILE="$TMP_GZ"; CHOSEN_EXT="gz"; CHOSEN_SIZE="$SIZE_GZ"
fi
if (( SIZE_XZ < CHOSEN_SIZE )); then
  CHOSEN_FILE="$TMP_XZ"; CHOSEN_EXT="xz"; CHOSEN_SIZE="$SIZE_XZ"
fi

echo "Valitud kompressor: $CHOSEN_EXT (suurus: $CHOSEN_SIZE baiti)."

# --- 7) Liigutame valitud arhiivi ja selle .sha256 faili lõppkausta ---
FINAL_ARCHIVE="$FINAL_PREFIX.tar.$CHOSEN_EXT"
FINAL_SHA256="$FINAL_ARCHIVE.sha256"

if [ -e "$FINAL_ARCHIVE" ] || [ -e "$FINAL_SHA256" ]; then
  echo "Viga: sihtfail juba eksisteerib: $(basename "$FINAL_ARCHIVE")."
  printf "[ %s ] BACKUP FAILED (exists %s)\n" "$(date '+%F %T')" "$FINAL_ARCHIVE" >> "$LOG_FILE"
  exit 1
fi

mv "$CHOSEN_FILE" "$FINAL_ARCHIVE"
mv "$CHOSEN_FILE.sha256" "$FINAL_SHA256"

# Valimata variandid koristame (ajutistest failidest hoolitseb trap niikuinii)
# (Jätame need ajutisse kausta; trap eemaldab.)

# --- 8) Lõplikud kontrollid sihtkettal ---
echo "Lõplik kontroll sihtfaililt:"
case "$CHOSEN_EXT" in
  zst) tar -I 'zstd -d' -tf "$FINAL_ARCHIVE" | head -n 5 >/dev/null ;;
  gz)  tar -tf "$FINAL_ARCHIVE" | head -n 5 >/dev/null ;;
  xz)  tar -tf "$FINAL_ARCHIVE" | head -n 5 >/dev/null ;;
esac

# Arvuta ja kontrolli uuesti kontrollsumma lõplikust failist
sha256sum "$FINAL_ARCHIVE" > "$FINAL_SHA256"
if sha256sum -c "$FINAL_SHA256"; then
  echo "Kontrollsumma vastab: OK"
else
  echo "Viga: kontrollsumma ei vasta lõppfailile!"
  printf "[ %s ] BACKUP FAILED (checksum mismatch at final)\n" "$(date '+%F %T')" >> "$LOG_FILE"
  exit 4
fi

# Kuvame inimloetava suuruse
ARCHIVE_SIZE_H=$(du -h "$FINAL_ARCHIVE" | awk '{print $1}')
echo "Valitud arhiiv: $FINAL_ARCHIVE"
echo "Arhiivi suurus: $ARCHIVE_SIZE_H"
echo "Kontrollsumma fail: $FINAL_SHA256"

# --- 9) Vana varukoopiate puhastus (alles 3 kõige uuemat sõltumata laiendist) ---
echo "Puhastan vanu varukoopiaid (alles jäävad ainult $KEEP_COUNT kõige uuemat)..."
cd "$BACKUP_DIR"
# Sorteerime kõik tar.* varundusfailid uueim-enne ja kustutame vanemad.
ls -1t src-*.tar.* 2>/dev/null | tail -n +$((KEEP_COUNT+1)) | xargs -r rm -f
# Juhuks kui sha256 jääb ilma paariliseta, piirame ka kontrollsumma faile
ls -1t src-*.tar.*.sha256 2>/dev/null | tail -n +$((KEEP_COUNT+3)) | xargs -r rm -f

echo "Alles olevad varukoopiad:"
ls -1t src-*.tar.* 2>/dev/null || echo "(ühtegi varukoopiat pole)"

# --- 10) Logi lõpp ---
printf "[ %s ] BACKUP END (chosen %s, size %s)\n" \
  "$(date '+%F %T')" "$CHOSEN_EXT" "$ARCHIVE_SIZE_H" >> "$LOG_FILE"

echo "Logi salvestatud faili: $LOG_FILE"
echo "Töö valmis."
