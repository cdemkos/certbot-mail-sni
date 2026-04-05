#!/bin/bash
set -e

echo "=== certbot-mail-sni Installation ==="

cp -f update-certbot-mail-sni.sh /usr/local/bin/update-certbot-mail-sni.sh
chmod +x /usr/local/bin/update-certbot-mail-sni.sh

# Einfacher Deploy-Hook anlegen
cat > /usr/local/bin/le-mail-deploy-hook.sh <<'HOOK'
#!/bin/bash
echo "$(date '+%Y-%m-%d %H:%M:%S') - Certbot Deploy-Hook → Starte SNI Update" >> /var/log/letsencrypt-renew.log
/usr/local/bin/update-certbot-mail-sni.sh
HOOK

chmod +x /usr/local/bin/le-mail-deploy-hook.sh

echo "Installation abgeschlossen."
echo "Verwende als --deploy-hook: /usr/local/bin/le-mail-deploy-hook.sh"
