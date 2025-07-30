🚀 Instructions de déploiement
1. Cloner le repository
bashgit clone https://github.com/your-org/syncthing-tailscale-deploy.git
cd syncthing-tailscale-deploy
2. Configuration
bashcp .env.example .env
nano .env  # Configurer vos tokens
3. Déploiement automatique
bashsudo ./bootstrap.sh --auto
4. Vérification
bash./scripts/verify_setup.sh
📱 Configuration client mobile

Installer Tailscale sur votre appareil mobile
Se connecter au même réseau Tailscale
Installer Syncthing sur mobile
Ajouter le serveur avec le Device ID affiché
Configurer la synchronisation du dossier Obsidian

🔄 Déployer un second VPS
bash# Sur le second VPS
export HOSTNAME_SUFFIX="02"
sudo ./bootstrap.sh --auto
Cette configuration permet une synchronisation peer-to-peer robuste avec redondance DNS automatique.
