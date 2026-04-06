certbot-mail-sni

Automatische SNI-Konfiguration für Postfix + Dovecot aus Certbot Zertifikaten.

Komplett unabhängig von ISPConfig.
Nutzt nur die Zertifikate unter /etc/letsencrypt/live/.
Installation auf dem Server
bash

sudo git clone https://github.com/cdemkos/certbot-mail-sni.git /opt/certbot-mail-snicd /opt/certbot-mail-snisudo ./install.sh

Hinweis: Das Installationsskript legt das Hauptskript typischerweise nach /usr/local/bin/update-certbot-mail-sni.sh ab. Achte beim Deploy-Hook darauf, dass der Pfad konsistent ist (siehe unten).
Nach der Installation

Beispiel für Certbot mit DNS-Validierung und Deploy-Hook. Verwende hier den Pfad, den dein Installationsskript tatsächlich gesetzt hat — z. B. /usr/local/bin/update-certbot-mail-sni.sh:
bash

sudo certbot certonly --manual \  --manual-auth-hook /etc/letsencrypt/acme-dns-auth.py \  --preferred-challenges dns \  --deploy-hook "/usr/local/bin/update-certbot-mail-sni.sh" \  -d "*.deinedomain.ch" \  -d "

Wichtig:

    Wildcard-Domains gelten für eine Ebene; verwende -d "*.deinedomain.ch" (nicht "*.mail.deinedomain.ch") zusammen mit der expliziten Subdomain -d "mail.deinedomain.ch", falls benötigt.
    Stelle sicher, dass der in --deploy-hook angegebene Pfad mit dem tatsächlichen Installationspfad übereinstimmt (z. B. /usr/local/bin/update-certbot-mail-sni.sh oder /opt/certbot-mail-sni/update-certbot-mail-sni.sh).

Voraussetzungen

    Postfix mit Unterstützung für tls_server_sni_maps (übliche Postfix-Versionen ab neueren Releases).
    Dovecot mit Unterstützung für SNI via local_name-Konfiguration.
    Lese-/Schreibrechte für die Zertifikatsdateien unter /etc/letsencrypt/live/.
    Das Installationsskript setzt die Skripte mit ausführbaren Rechten; Deploy-Hook muss vom Certbot-Prozess ausgeführt werden können.

