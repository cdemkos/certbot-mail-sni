# certbot-mail-sni

Automatische SNI-Konfiguration für **Postfix** + **Dovecot** aus Certbot Zertifikaten.

Komplett unabhängig von ISPConfig.  
Nutzt nur die Zertifikate unter `/etc/letsencrypt/live/`.

## Installation auf dem Server

```bash
sudo git clone https://github.com/cdemkos/certbot-mail-sni.git /opt/certbot-mail-sni
cd /opt/certbot-mail-sni
sudo ./install.sh
```
## Nach der Installation

```bash
sudo certbot certonly --manual \
  --manual-auth-hook /etc/letsencrypt/acme-dns-auth.py \
  --preferred-challenges dns \
  --deploy-hook "/opt/certbot-mail-sni/update-certbot-mail-sni.sh" \
  -d "*.mail.deinedomain.ch" \
  -d "mail.deinedomain.ch"
```
