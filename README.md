# certbot-mail-sni

Automatische SNI-Konfiguration für **Postfix** + **Dovecot** aus Certbot/Let's Encrypt Zertifikaten.

Funktioniert komplett unabhängig von ISPConfig.  
Nutzt ausschließlich die Zertifikate unter `/etc/letsencrypt/live/`.

## Features
- Scannt automatisch alle Zertifikate in `/etc/letsencrypt/live/`
- Erstellt `tls_server_sni_maps` für Postfix
- Erstellt `local_name {}` Blöcke für Dovecot
- Nur bei echten Änderungen werden Dateien und Dienste neu gestartet
- Kompatibel mit Wildcard-Zertifikaten und einzelnen Domains
- Wird über Certbot `--deploy-hook` automatisch ausgeführt

## Installation

```bash
git clone https://github.com/cdemkos/certbot-mail-sni.git /opt/certbot-mail-sni
cd /opt/certbot-mail-sni
sudo ./update-certbot-mail-sni.sh
