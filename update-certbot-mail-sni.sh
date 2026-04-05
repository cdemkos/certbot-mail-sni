sudo cat > /usr/local/bin/update-certbot-mail-sni.sh <<'EOF'
#!/bin/bash
# ================================================================
# update-certbot-mail-sni.sh
# Automatische SNI-Konfiguration für Postfix + Dovecot aus Certbot
# Zertifikate liegen unter /etc/letsencrypt/live/
# ================================================================

set -euo pipefail

DOVECOT_SNI_CONF="/etc/dovecot/conf.d/99-certbot-mail-sni.conf"
POSTFIX_SNI_MAP="/etc/postfix/vmail_ssl.map"
LIVE_DIR="/etc/letsencrypt/live"

log() {
    logger -t "certbot-mail-sni" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Temporäre Dateien
TMP_DOVECOT=$(mktemp)
TMP_POSTFIX=$(mktemp)

# Alle Zertifikate finden (alle Ordner unter live/ die fullchain + privkey haben)
find "$LIVE_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r certdir; do
    domain=$(basename "$certdir")
    fullchain="$certdir/fullchain.pem"
    privkey="$certdir/privkey.pem"

    if [[ -f "$fullchain" && -f "$privkey" ]]; then
        log "Gefunden: $domain"

        # Dovecot local_name Block
        cat >> "$TMP_DOVECOT" <<EOD

local_name $domain {
    ssl_cert = <$fullchain
    ssl_key  = <$privkey
}
EOD

        # Postfix tls_server_sni_maps Eintrag
        echo "$domain $privkey $fullchain" >> "$TMP_POSTFIX"
    fi
done

# Dovecot Konfig schreiben
cat > "$TMP_DOVECOT" <<'HEADER'
# Automatisch generiert von update-certbot-mail-sni.sh
# Nicht manuell bearbeiten!
HEADER
cat "$TMP_DOVECOT" >> "$TMP_DOVECOT" 2>/dev/null || true

if ! cmp -s "$TMP_DOVECOT" "$DOVECOT_SNI_CONF" 2>/dev/null; then
    mv "$TMP_DOVECOT" "$DOVECOT_SNI_CONF"
    log "Dovecot SNI Konfiguration aktualisiert"
    DOVECOT_CHANGED=1
else
    rm -f "$TMP_DOVECOT"
    DOVECOT_CHANGED=0
fi

# Postfix Map schreiben
cat > "$TMP_POSTFIX" <<'HEADER'
# Automatisch generiert von update-certbot-mail-sni.sh
# Format: hostname privkey fullchain
HEADER
cat "$TMP_POSTFIX" >> "$TMP_POSTFIX" 2>/dev/null || true

if ! cmp -s "$TMP_POSTFIX" "$POSTFIX_SNI_MAP" 2>/dev/null; then
    mv "$TMP_POSTFIX" "$POSTFIX_SNI_MAP"
    postmap -F hash:"$POSTFIX_SNI_MAP"
    log "Postfix SNI Map aktualisiert"
    POSTFIX_CHANGED=1
else
    rm -f "$TMP_POSTFIX"
    POSTFIX_CHANGED=0
fi

# Postfix Haupt-Konfig sicherstellen
if ! postconf -h tls_server_sni_maps 2>/dev/null | grep -q "vmail_ssl.map"; then
    postconf -e "tls_server_sni_maps = hash:$POSTFIX_SNI_MAP"
    log "tls_server_sni_maps in main.cf aktiviert"
    POSTFIX_CHANGED=1
fi

# Dienste nur neu starten, wenn wirklich etwas geändert wurde
if [ "$DOVECOT_CHANGED" = "1" ] || [ "$POSTFIX_CHANGED" = "1" ]; then
    log "Konfiguration geändert → Dienste werden neu gestartet"
    systemctl restart dovecot
    systemctl restart postfix
    log "Postfix und Dovecot neu gestartet"
else
    log "Keine Änderungen → keine Neustarts nötig"
fi

log "SNI-Update abgeschlossen"
EOF

sudo chmod +x /usr/local/bin/update-certbot-mail-sni.sh
