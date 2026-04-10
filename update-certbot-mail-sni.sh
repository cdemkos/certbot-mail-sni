#!/bin/bash
# =============================================================================
# update-certbot-mail-sni.sh — ISPConfig-kompatible SNI-Konfiguration
# Basiert auf: https://github.com/cdemkos/certbot-mail-sni
# Angepasst für ISPConfig + Dovecot auf Debian
#
# Fixes gegenüber Original:
#  - Subshell-Bug bei DOVECOT_CHANGED/POSTFIX_CHANGED behoben (Tempfile statt Pipe)
#  - Backup der bestehenden Konfiguration vor jeder Änderung
#  - Validierung der Dovecot-Konfiguration vor Neustart (doveconf -n)
#  - Kein Überschreiben von ISPConfig-verwalteten Dateien (10-ssl.conf bleibt unberührt)
#  - Bereinigung der alten/leeren SNI-Conf wenn keine Zertifikate gefunden
#  - Bessere Fehlerbehandlung mit Rollback
# =============================================================================

set -uo pipefail

# --- Konfiguration -----------------------------------------------------------
DOVECOT_SNI_CONF="/etc/dovecot/conf.d/99-certbot-mail-sni.conf"
POSTFIX_SNI_MAP="/etc/postfix/vmail_ssl.map"
LIVE_DIR="/etc/letsencrypt/live"
BACKUP_DIR="/var/backups/certbot-mail-sni"
LOG_TAG="certbot-mail-sni"

# --- Hilfsfunktionen ---------------------------------------------------------
log() {
    logger -t "$LOG_TAG" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LOG_TAG] $1"
}

die() {
    log "FEHLER: $1"
    exit 1
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        local backup="${BACKUP_DIR}/$(basename "$file").$(date '+%Y%m%d_%H%M%S').bak"
        cp "$file" "$backup"
        log "Backup erstellt: $backup"
    fi
}

# --- Root-Check --------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    die "Dieses Skript muss als root ausgeführt werden."
fi

# --- Temporäre Dateien -------------------------------------------------------
TMP_DOVECOT=$(mktemp)
TMP_POSTFIX=$(mktemp)
TMP_CHANGED=$(mktemp)   # Workaround für Subshell-Variable-Bug
echo "DOVECOT_CHANGED=0" > "$TMP_CHANGED"
echo "POSTFIX_CHANGED=0" >> "$TMP_CHANGED"

trap 'rm -f "$TMP_DOVECOT" "$TMP_POSTFIX" "$TMP_CHANGED"' EXIT

# --- Zertifikate einlesen (ohne Subshell-Pipe!) ------------------------------
# Wichtig: "find ... | while read" erzeugt eine Subshell → Variablen gehen verloren.
# Lösung: Prozesssubstitution "while read < <(find ...)"
FOUND_COUNT=0

while IFS= read -r certdir; do
    domain=$(basename "$certdir")

    # Nur mail.* Domains verarbeiten
    if [[ "$domain" != mail.* ]]; then
        continue
    fi

    fullchain="$certdir/fullchain.pem"
    privkey="$certdir/privkey.pem"

    if [[ ! -f "$fullchain" ]]; then
        log "WARNUNG: $domain — fullchain.pem nicht gefunden, übersprungen"
        continue
    fi
    if [[ ! -f "$privkey" ]]; then
        log "WARNUNG: $domain — privkey.pem nicht gefunden, übersprungen"
        continue
    fi
    if [[ ! -r "$fullchain" ]]; then
        log "WARNUNG: $domain — fullchain.pem nicht lesbar (Berechtigungen?), übersprungen"
        continue
    fi
    if [[ ! -r "$privkey" ]]; then
        log "WARNUNG: $domain — privkey.pem nicht lesbar (Berechtigungen?), übersprungen"
        continue
    fi

    log "Zertifikat gefunden: $domain"
    FOUND_COUNT=$((FOUND_COUNT + 1))

    # Dovecot SNI Block
    cat >> "$TMP_DOVECOT" <<EOD

local_name $domain {
  ssl_cert = <$fullchain
  ssl_key = <$privkey
}
EOD

    # Postfix SNI Zeile (privkey ZUERST — Postfix erwartet: domain privkey fullchain)
    printf '%s %s %s\n' "$domain" "$privkey" "$fullchain" >> "$TMP_POSTFIX"

done < <(find "$LIVE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

log "$FOUND_COUNT mail.* Zertifikat(e) verarbeitet"

# --- Dovecot SNI Konfiguration -----------------------------------------------
if [[ "$FOUND_COUNT" -eq 0 ]]; then
    # Keine Zertifikate → leere/alte Conf entfernen damit Dovecot nicht bricht
    if [[ -f "$DOVECOT_SNI_CONF" ]]; then
        log "Keine mail.* Zertifikate gefunden — entferne alte SNI-Konfiguration"
        backup_file "$DOVECOT_SNI_CONF"
        rm -f "$DOVECOT_SNI_CONF"
        sed -i "\|$POSTFIX_SNI_MAP|d" /etc/postfix/main.cf 2>/dev/null || true
        log "Alte Konfiguration bereinigt"
    else
        log "Keine Zertifikate und keine alte Konfiguration — nichts zu tun"
    fi
    exit 0
fi

DOVECOT_CHANGED=0
POSTFIX_CHANGED=0

if ! cmp -s "$TMP_DOVECOT" "$DOVECOT_SNI_CONF" 2>/dev/null; then
    backup_file "$DOVECOT_SNI_CONF"
    install -m 644 "$TMP_DOVECOT" "$DOVECOT_SNI_CONF"
    log "Dovecot SNI Konfiguration aktualisiert: $DOVECOT_SNI_CONF"
    DOVECOT_CHANGED=1
else
    log "Dovecot SNI Konfiguration unverändert"
fi

# --- Dovecot Konfiguration validieren BEVOR neu gestartet wird ---------------
if [[ "$DOVECOT_CHANGED" -eq 1 ]]; then
    if ! doveconf -n > /dev/null 2>&1; then
        log "FEHLER: Dovecot Konfiguration ungültig! Rollback..."
        if [[ -f "${BACKUP_DIR}/99-certbot-mail-sni.conf."* ]]; then
            # Neuestes Backup wiederherstellen
            latest_backup=$(ls -t "${BACKUP_DIR}/99-certbot-mail-sni.conf."*.bak 2>/dev/null | head -1)
            if [[ -n "$latest_backup" ]]; then
                cp "$latest_backup" "$DOVECOT_SNI_CONF"
                log "Backup wiederhergestellt: $latest_backup"
            else
                rm -f "$DOVECOT_SNI_CONF"
                log "Kein Backup vorhanden — SNI-Conf gelöscht (Dovecot startet mit Standard-SSL)"
            fi
        fi
        die "Dovecot Konfiguration ist fehlerhaft — Neustart abgebrochen. Prüfe: doveconf -n"
    fi
    log "Dovecot Konfiguration validiert ✓"
fi

# --- Postfix SNI Map ---------------------------------------------------------
# texthash: wird direkt gelesen, kein postmap nötig
if ! cmp -s "$TMP_POSTFIX" "$POSTFIX_SNI_MAP" 2>/dev/null; then
    backup_file "$POSTFIX_SNI_MAP"
    install -m 644 "$TMP_POSTFIX" "$POSTFIX_SNI_MAP"
    log "Postfix SNI Map aktualisiert: $POSTFIX_SNI_MAP"
    POSTFIX_CHANGED=1
else
    log "Postfix SNI Map unverändert"
fi

# tls_server_sni_maps in main.cf setzen falls noch nicht vorhanden oder falsches Format
if ! postconf -h tls_server_sni_maps 2>/dev/null | grep -qF "texthash:$POSTFIX_SNI_MAP"; then
    postconf -e "tls_server_sni_maps = texthash:$POSTFIX_SNI_MAP"
    log "tls_server_sni_maps in main.cf gesetzt (texthash)"
    POSTFIX_CHANGED=1
fi

# --- Dienste neu starten -----------------------------------------------------
if [[ "$DOVECOT_CHANGED" -eq 1 ]]; then
    log "Starte Dovecot neu..."
    systemctl restart dovecot || die "Dovecot Neustart fehlgeschlagen! Prüfe: journalctl -u dovecot -n 30"
    log "Dovecot erfolgreich neu gestartet ✓"
fi

if [[ "$POSTFIX_CHANGED" -eq 1 ]]; then
    log "Lade Postfix neu..."
    systemctl reload postfix || die "Postfix reload fehlgeschlagen"
    log "Postfix erfolgreich neu geladen ✓"
fi

if [[ "$DOVECOT_CHANGED" -eq 0 && "$POSTFIX_CHANGED" -eq 0 ]]; then
    log "Keine Änderungen erkannt — kein Neustart nötig"
fi

log "SNI-Update abgeschlossen ($FOUND_COUNT Zertifikat(e) konfiguriert)"
