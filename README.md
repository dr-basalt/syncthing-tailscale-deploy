# 🔄 Syncthing + Tailscale VPS ARM64 Deployment

Déploiement automatisé d'un service Syncthing sécurisé via Tailscale sur VPS ARM64.

## 🎯 Fonctionnalités

- ✅ Syncthing protégé par VPN Tailscale
- ✅ Support mobile (iOS/Android) et desktop
- ✅ Synchronisation bidirectionnelle peer-to-peer
- ✅ DNS Cloudflare automatique avec round-robin
- ✅ Déploiement reproductible sur plusieurs VPS
- ✅ Optimisé ARM64 (≤ 512MB RAM)
- ✅ HTTPS intégré ou Caddy SSL reverse proxy
- ✅ Certificats SSL automatiques (optionnel)

## 🚀 Installation rapide

### Mode automatique (recommandé) - HTTPS Syncthing intégré
```bash
git clone https://github.com/your-org/syncthing-tailscale-deploy.git
cd syncthing-tailscale-deploy
cp .env.example .env
# Éditez .env avec vos tokens (gardez ENABLE_CADDY="false")
sudo ./bootstrap.sh --auto
Mode automatique avec Caddy SSL
bashgit clone https://github.com/your-org/syncthing-tailscale-deploy.git
cd syncthing-tailscale-deploy
cp .env.example .env
# Éditez .env avec vos tokens et ENABLE_CADDY="true"
sudo ./bootstrap.sh --auto
Mode interactif
bashsudo ./bootstrap.sh
🔧 Configuration requise

Cloudflare API Token avec permissions :

Zone:Zone:Read
Zone:DNS:Edit
(Le Zone ID sera détecté automatiquement)


Tailscale Auth Key :

Généré sur https://login.tailscale.com/admin/settings/keys
Préférer un token réutilisable


VPS ARM64 supportés :

Oracle Cloud (Always Free)
Scaleway ARM64
Hetzner ARM64



📋 Variables d'environnement
Copiez .env.example vers .env et configurez :
bash# Cloudflare
CF_API_TOKEN="your_cloudflare_api_token"
DOMAIN_ROOT="ori3com.cloud"

# Tailscale
TAILSCALE_AUTH_KEY="your_tailscale_auth_key"

# Déploiement
HOSTNAME_SUFFIX="01"  # ou "02" pour le second VPS
SERVER_NAME="vpn-syncthing-${HOSTNAME_SUFFIX}"

# HTTPS/SSL
ENABLE_CADDY="false"  # true pour SSL automatique via Caddy
🔒 Options HTTPS/SSL
Option 1 : HTTPS Syncthing intégré (Par défaut)
bashENABLE_CADDY="false"

✅ HTTPS activé automatiquement
⚠️ Certificat auto-signé (alerte navigateur)
🔒 Sécurisé via Tailscale VPN

Option 2 : Caddy SSL Reverse Proxy (Recommandé)
bashENABLE_CADDY="true"

✅ Certificats SSL automatiques
✅ Pas d'alerte navigateur
✅ Redirections automatiques
✅ Headers de sécurité
🔧 Configuration avancée possible

🔍 Vérification post-installation
bash./scripts/verify_setup.sh
🌐 Accès aux services
Avec HTTPS Syncthing intégré (ENABLE_CADDY="false")

Syncthing Web UI : https://100.109.xxx.xxx:8384 (via Tailscale)
DNS sécurisé : https://syncthing-XX.ori3com.cloud:8384 (via Tailscale)
⚠️ Acceptez l'alerte de certificat dans le navigateur

Avec Caddy SSL (ENABLE_CADDY="true")

URL principale : https://syncthing-XX.ori3com.cloud
Redirections automatiques depuis tous les autres domaines
✅ Certificats SSL valides (pas d'alerte navigateur)
🔒 Accessible uniquement via Tailscale

DNS Round Robin (les deux modes)

vpn-syncthing.ori3com.cloud
syncthing.ori3com.cloud

📱 Configuration mobile

Installez Tailscale sur mobile
Connectez-vous au même réseau Tailscale
Installez Syncthing sur mobile
Ajoutez le device ID du VPS dans Syncthing mobile

🔄 Déployer un second VPS
bash# Sur le second VPS
export HOSTNAME_SUFFIX="02"
sudo ./bootstrap.sh --auto
🛠️ Gestion des services
Syncthing
bash# Status et logs
docker ps | grep syncthing
docker logs syncthing

# Redémarrer
docker-compose restart syncthing
Tailscale
bash# Status
sudo tailscale status

# Redémarrer
sudo systemctl restart tailscaled
Caddy (si activé)
bash# Status
sudo systemctl status caddy

# Redémarrer
sudo systemctl restart caddy

# Logs
sudo journalctl -u caddy -f
tail -f /var/log/caddy/syncthing.log

# Configuration
sudo nano /etc/caddy/Caddyfile
sudo caddy reload

# Activer Let's Encrypt (certificats publics valides)
# Éditer /etc/caddy/conf.d/syncthing.conf et commenter la ligne :
# tls internal
# Puis redémarrer : sudo systemctl restart caddy
Activation Let's Encrypt (optionnel)
Pour des certificats SSL publics au lieu des certificats auto-signés :
bash# 1. Éditer la configuration Caddy
sudo nano /etc/caddy/conf.d/syncthing.conf

# 2. Commenter ou supprimer la ligne :
# tls internal

# 3. Redémarrer Caddy
sudo systemctl restart caddy

# 4. Vérifier les logs
sudo journalctl -u caddy -f
⚠️ Note : Let's Encrypt nécessite que votre domaine soit accessible depuis internet (port 80/443).
🛠️ Troubleshooting
Vérifier Tailscale
bashsudo tailscale status
Vérifier Syncthing
bashdocker logs syncthing
Vérifier DNS
bashdig vpn-syncthing.ori
