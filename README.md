# 🔄 Syncthing + Tailscale VPS ARM64 Deployment

Déploiement automatisé d'un service Syncthing sécurisé via Tailscale sur VPS ARM64.

## 🎯 Fonctionnalités

- ✅ Syncthing protégé par VPN Tailscale
- ✅ Support mobile (iOS/Android) et desktop
- ✅ Synchronisation bidirectionnelle peer-to-peer
- ✅ DNS Cloudflare automatique avec round-robin
- ✅ Déploiement reproductible sur plusieurs VPS
- ✅ Optimisé ARM64 (≤ 512MB RAM)

## 🚀 Installation rapide

### Mode automatique (recommandé)
```bash
git clone https://github.com/your-org/syncthing-tailscale-deploy.git
cd syncthing-tailscale-deploy
cp .env.example .env
# Éditez .env avec vos tokens
sudo ./bootstrap.sh --auto
