#!/usr/bin/env bash
# MARKET EMPIRE Online – Einrichtung auf einem frischen Debian-/Ubuntu-Server (als root ausführen):
#   curl -fsSL https://achistyle-art.github.io/market-empire-releases/install.sh | bash
# Installiert Docker, startet Spiel + Spielserver mit Caddy (HTTPS über Let's Encrypt) und richtet eine
# tägliche Datensicherung ein. Mehrfaches Ausführen ist unbedenklich (aktualisiert auf die neueste Version).
set -euo pipefail

# Alles in einer Funktion: Bei „curl | bash“ liest bash so das ganze Skript ein, bevor ein Befehl
# (z. B. docker exec) die Standardeingabe lesen und den Rest des Skripts verschlucken kann.
main() {

DIR=/opt/market-empire

say() { printf '\n\033[1;32m▶ %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Bitte als root ausführen (z. B. nach „sudo -i“)."
command -v apt-get >/dev/null || fail "Dieses Skript ist für Debian/Ubuntu gedacht."

# Fragen lesen auch dann vom Terminal, wenn das Skript per „curl | bash“ läuft
ask() { local prompt="$1" def="$2" ans=""; read -r -p "$prompt" ans </dev/tty || true; echo "${ans:-$def}"; }

mkdir -p "$DIR"
DOMAIN=""; ADMINS=""; SMTP_BENUTZER=""; SMTP_HOST=""; SMTP_PORT=""
[ -f "$DIR/.env" ] && . "$DIR/.env"
if [ -z "${MARKET_EMPIRE_UNATTENDED:-}" ]; then
  echo
  echo "MARKET EMPIRE Online – Einrichtung"
  echo "Domain leer lassen, um zunächst ohne Domain über http://<Server-IP> zu testen."
  DOMAIN=$(ask "Domain für das Spiel (z. B. spiel.example.de) [${DOMAIN:-keine}]: " "$DOMAIN")
  ADMINS=$(ask "Spielername(n) mit Moderationsrechten, kommagetrennt [${ADMINS:-keine}]: " "$ADMINS")
  echo
  echo "E-Mail-Versand (Bestätigungscodes bei der Registrierung, „Passwort vergessen“)."
  echo "Postfach leer lassen = ohne E-Mail-Bestätigung. Bei IONOS: smtp.ionos.de, Port 587."
  SMTP_BENUTZER=$(ask "Absender-Postfach (z. B. game@cargesia.com) [${SMTP_BENUTZER:-keins}]: " "$SMTP_BENUTZER")
  if [ -n "$SMTP_BENUTZER" ]; then
    SMTP_HOST=$(ask "SMTP-Server [${SMTP_HOST:-smtp.ionos.de}]: " "${SMTP_HOST:-smtp.ionos.de}")
    SMTP_PORT=$(ask "SMTP-Port (587 = STARTTLS, 465 = SSL) [${SMTP_PORT:-587}]: " "${SMTP_PORT:-587}")
    PW_HINWEIS="neu eingeben"; [ -s "$DIR/smtp-passwort" ] && PW_HINWEIS="leer lassen = bisheriges behalten"
    PW=""; read -r -s -p "Passwort des Postfachs ($PW_HINWEIS, Eingabe bleibt unsichtbar): " PW </dev/tty || true; echo
    if [ -n "$PW" ]; then (umask 077; printf '%s' "$PW" > "$DIR/smtp-passwort"); fi
    unset PW
    [ -s "$DIR/smtp-passwort" ] || fail "Ohne Passwort kann der Server keine E-Mails senden. Bitte das Skript erneut starten."
  fi
fi
# Eingaben wie „https://spiel.example.de/“ auf den reinen Domainnamen kürzen
DOMAIN=$(printf '%s' "$DOMAIN" | sed -E 's#^[A-Za-z]+://##; s#/.*$##; s#:.*$##' | tr -d '[:space:]' | tr 'A-Z' 'a-z')
ADMINS=$(printf '%s' "$ADMINS" | tr -d '[:space:]')
case "$DOMAIN" in *[!A-Za-z0-9.-]*) fail "Ungültige Domain: $DOMAIN" ;; esac
case "$ADMINS" in *[!A-Za-z0-9ÄÖÜäöüß_.,-]*) fail "Ungültige Spielernamen: $ADMINS" ;; esac
SMTP_BENUTZER=$(printf '%s' "$SMTP_BENUTZER" | tr -d '[:space:]')
case "$SMTP_BENUTZER" in ""|*@*.*) ;; *) fail "Ungültiges Postfach: $SMTP_BENUTZER" ;; esac
case "$SMTP_BENUTZER$SMTP_HOST$SMTP_PORT" in *[!A-Za-z0-9@._+-]*) fail "Ungültige SMTP-Angaben" ;; esac
[ -n "$SMTP_BENUTZER" ] || { SMTP_HOST=""; SMTP_PORT=""; }

say "System aktualisieren und Docker installieren"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg >/dev/null
if ! command -v docker >/dev/null; then
  . /etc/os-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
fi
systemctl enable --now docker >/dev/null

say "Konfiguration schreiben ($DIR)"
printf 'DOMAIN=%s\nADMINS=%s\nSMTP_BENUTZER=%s\nSMTP_HOST=%s\nSMTP_PORT=%s\n' "$DOMAIN" "$ADMINS" "$SMTP_BENUTZER" "$SMTP_HOST" "$SMTP_PORT" > "$DIR/.env"
chmod 600 "$DIR/.env"
# Passwortdatei: nur für den Spielserver lesbar (läuft im Container als Benutzer „node“, UID 1000)
touch "$DIR/smtp-passwort"; chown 1000:1000 "$DIR/smtp-passwort"; chmod 600 "$DIR/smtp-passwort"

if [ -n "$DOMAIN" ]; then SITE="$DOMAIN"; else SITE=":80"; fi
cat > "$DIR/Caddyfile" <<EOF
# Ohne Domain (":80") nur HTTP – für den ersten Test. Mit Domain holt Caddy automatisch ein HTTPS-Zertifikat.
$SITE {
	encode gzip
	reverse_proxy spiel:3100
	request_body {
		max_size 10MB
	}
}
EOF

cat > "$DIR/docker-compose.yml" <<'EOF'
services:
  spiel:
    image: ghcr.io/achistyle-art/market-empire-server:latest
    restart: unless-stopped
    environment:
      ADMINS: "${ADMINS:-}"
      SMTP_HOST: "${SMTP_HOST:-}"
      SMTP_PORT: "${SMTP_PORT:-587}"
      SMTP_BENUTZER: "${SMTP_BENUTZER:-}"
      SMTP_ABSENDER: "MARKET EMPIRE <${SMTP_BENUTZER:-}>"
      SMTP_PASSWORT_DATEI: /run/smtp-passwort
    volumes:
      - spiel-daten:/app/data
      - ./smtp-passwort:/run/smtp-passwort:ro
  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-daten:/data
    depends_on:
      - spiel
volumes:
  spiel-daten:
  caddy-daten:
EOF

say "Spiel herunterladen"
cd "$DIR"
if ! docker compose pull </dev/null 2>/tmp/me-pull.log; then
  if grep -qiE 'denied|unauthorized' /tmp/me-pull.log; then
    fail "Das Spiel-Image ist noch nicht öffentlich. Auf GitHub unter Packages → market-empire-server → Package settings → „Change visibility“ auf Public stellen und das Skript erneut starten."
  fi
  cat /tmp/me-pull.log
  fail "Herunterladen fehlgeschlagen."
fi

say "Spiel starten"
docker compose up -d --remove-orphans </dev/null

say "Tägliche Datensicherung einrichten"
cat > /etc/cron.daily/market-empire-sicherung <<'EOF'
#!/bin/sh
# Sicherung der Spieldatenbank (Konten, Cloud-Spielstände, Bestenlisten); die letzten 14 bleiben erhalten.
cd /opt/market-empire || exit 0
docker compose exec -T spiel node -e "
const fs = require('node:fs'); const { DatabaseSync } = require('node:sqlite');
fs.mkdirSync('/app/data/backups', { recursive: true });
const ziel = '/app/data/backups/spiel-' + new Date().toISOString().slice(0, 10) + '.sqlite';
fs.rmSync(ziel, { force: true });
new DatabaseSync('/app/data/market-empire.sqlite').exec(\"VACUUM INTO '\" + ziel + \"'\");
const alle = fs.readdirSync('/app/data/backups').filter((f) => f.startsWith('spiel-')).sort();
for (const f of alle.slice(0, -14)) fs.rmSync('/app/data/backups/' + f);
" 2>/dev/null
EOF
chmod 755 /etc/cron.daily/market-empire-sicherung

say "Prüfen"
IP=$(curl -fsS -4 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
ok=""
for _ in $(seq 1 30); do
  if docker compose exec -T spiel wget -qO- http://127.0.0.1:3100/api/status </dev/null >/dev/null 2>&1; then ok=1; break; fi
  sleep 2
done
[ -n "$ok" ] || { docker compose logs --tail 50 spiel </dev/null; fail "Der Spielserver antwortet nicht."; }

echo
echo "✅ MARKET EMPIRE läuft."
if [ -n "$DOMAIN" ]; then
  DNS=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}' || true)
  echo "   Adresse: https://$DOMAIN"
  if [ "$DNS" != "$IP" ]; then
    echo "   ⚠️  $DOMAIN zeigt noch nicht auf diesen Server ($IP, DNS: ${DNS:-kein Eintrag})."
    echo "      Im DNS einen A-Eintrag für $DOMAIN auf $IP setzen. Das HTTPS-Zertifikat holt Caddy, sobald er greift."
  fi
else
  echo "   Test ohne Domain: http://$IP"
fi
if [ -n "$SMTP_BENUTZER" ]; then
  echo "   E-Mails gehen über $SMTP_HOST als $SMTP_BENUTZER. Test: Admin-Bereich → „Test-Mail senden“."
else
  echo "   E-Mail-Versand nicht eingerichtet: Konten werden ohne E-Mail-Bestätigung angelegt."
fi
echo "   Ports 80 und 443 müssen in der Firewall des Anbieters offen sein (IONOS: Cloud Panel → Netzwerk → Firewall-Richtlinien)."
echo "   Aktualisieren: dieses Skript erneut ausführen. Protokolle: cd $DIR && docker compose logs -f"
}

main "$@"
