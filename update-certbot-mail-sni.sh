#!/bin/bash
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

> "$TMP_DOVECOT"
> "$TMP_POSTFIX"

find "$LIVE_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r certdir; do
    domain=$(basename "$certdir")
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

        printf '%s %s %s\n' "$domain" "$fullchain" "$privkey" >> "$TMP_POSTFIX"
    else
        log "Ungültige Zertifikatsdateien für $domain — übersprungen"
    fi
done

if ! cmp -s "$TMP_DOVECOT" "$DOVECOT_SNI_CONF" 2>/dev/null; then
    install -m 644 "$TMP_DOVECOT" "$DOVECOT_SNI_CONF"
    log "Dovecot SNI Konfiguration aktualisiert"
    DOVECOT_CHANGED=1
else
    DOVECOT_CHANGED=0
fi

if ! cmp -s "$TMP_POSTFIX" "$POSTFIX_SNI_MAP" 2>/dev/null; then
    install -m 644 "$TMP_POSTFIX" "$POSTFIX_SNI_MAP"
    postmap "$POSTFIX_SNI_MAP"
    log "Postfix SNI Map aktualisiert + neu gehasht"
    POSTFIX_CHANGED=1
else
    postmap "$POSTFIX_SNI_MAP"
    POSTFIX_CHANGED=0
fi

if ! postconf -h tls_server_sni_maps 2>/dev/null | grep -q "$POSTFIX_SNI_MAP"; then
    postconf -e "tls_server_sni_maps = hash:$POSTFIX_SNI_MAP"
    log "tls_server_sni_maps in main.cf gesetzt"
    POSTFIX_CHANGED=1
fi

if [ "${DOVECOT_CHANGED:-0}" = "1" ] || [ "${POSTFIX_CHANGED:-0}" = "1" ]; then
    log "Konfiguration geändert → Dienste neu starten"
    systemctl restart dovecot postfix
    log "Postfix und Dovecot neu gestartet"
else
    log "Keine Änderungen erkannt"
fi

log "SNI-Update abgeschlossen (nur mail.* Zertifikate)"
