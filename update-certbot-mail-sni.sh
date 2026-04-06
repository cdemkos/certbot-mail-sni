#!/bin/bash
# ================================================================
# update-certbot-mail-sni.sh
# Automatische SNI-Konfiguration für Postfix + Dovecot aus Certbot
# FILTER: Nur Domains, die mit "mail." beginnen (z. B. mail.webseite.xxx)
# ================================================================

set -euo pipefail

DOVECOT_SNI_CONF="/etc/dovecot/conf.d/99-certbot-mail-sni.conf"
POSTFIX_SNI_MAP="/etc/postfix/vmail_ssl.map"
LIVE_DIR="/etc/letsencrypt/live"

log() {
    logger -t "certbot-mail-sni" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

TMP_DOVECOT=$(mktemp)
TMP_POSTFIX=$(mktemp)

trap 'rm -f "$TMP_DOVECOT" "$TMP_POSTFIX"' EXIT

# ── Header zuerst schreiben (wichtiger Fix zum Original-Skript) ──
cat > "$TMP_DOVECOT" <<'HEADER'
# Automatisch generiert von update-certbot-mail-sni.sh
# Nur mail.* Zertifikate - Nicht manuell bearbeiten!
HEADER

cat > "$TMP_POSTFIX" <<'HEADER'
# Automatisch generiert von update-certbot-mail-sni.sh
# Nur mail.* Zertifikate - Format: hostname fullchain privkey
HEADER

# ── Nur Ordner, die mit "mail." beginnen ──
find "$LIVE_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r certdir; do
    domain=$(basename "$certdir")
    
    # Nur Domains, die mit mail. beginnen
    if [[ "$domain" != mail.* ]]; then
        continue
    fi

    fullchain="$certdir/fullchain.pem"
    privkey="$certdir/privkey.pem"

    if [[ -f "$fullchain" && -f "$privkey" ]]; then
        log "Gefunden und aktiviert: $domain"

        cat >> "$TMP_DOVECOT" <<EOD

local_name $domain {
    ssl_cert = <$fullchain
    ssl_key  = <$privkey
}
EOD

        # Postfix erwartet: hostname certfile [keyfile] — hier: fullchain then privkey
        echo "$domain $fullchain $privkey" >> "$TMP_POSTFIX"
    else
        log "Ungültige Zertifikatsdateien für $domain — übersprungen"
    fi
done

# ── Dovecot Konfiguration ──
if ! cmp -s "$TMP_DOVECOT" "$DOVECOT_SNI_CONF" 2>/dev/null; then
    install -m 644 "$TMP_DOVECOT" "$DOVECOT_SNI_CONF"
    log "Dovecot SNI Konfiguration aktualisiert"
    DOVECOT_CHANGED=1
else
    DOVECOT_CHANGED=0
fi

# ── Postfix Map + postmap ──
if ! cmp -s "$TMP_POSTFIX" "$POSTFIX_SNI_MAP" 2>/dev/null; then
    install -m 644 "$TMP_POSTFIX" "$POSTFIX_SNI_MAP"
    # Erzeuge die .db mit postmap
    postmap "$POSTFIX_SNI_MAP"
    log "Postfix SNI Map aktualisiert"
    POSTFIX_CHANGED=1
else
    POSTFIX_CHANGED=0
fi

# ── tls_server_sni_maps in main.cf sicherstellen (aktueller Standard) ──
current=$(postconf -h tls_server_sni_maps 2>/dev/null || true)
if [[ "$current" != *"$POSTFIX_SNI_MAP"* ]]; then
    postconf -e "tls_server_sni_maps = hash:$POSTFIX_SNI_MAP"
    log "tls_server_sni_maps in main.cf gesetzt"
    POSTFIX_CHANGED=1
fi

# ── Nur bei echten Änderungen neu starten ──
if [ "${DOVECOT_CHANGED:-0}" = "1" ] || [ "${POSTFIX_CHANGED:-0}" = "1" ]; then
    log "Konfiguration geändert → Dienste neu starten"
    systemctl restart dovecot postfix
    log "Postfix und Dovecot neu gestartet"
else
    log "Keine Änderungen erkannt"
fi

log "SNI-Update abgeschlossen (nur mail.* Zertifikate)"

