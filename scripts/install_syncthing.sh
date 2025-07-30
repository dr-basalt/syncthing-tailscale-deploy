#!/bin/bash
set -euo pipefail

# 📦 Syncthing Installation Script with Docker (ARM64 optimized)

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[SYNCTHING] $1${NC}"
}

error() {
    echo -e "${RED}[SYNCTHING ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[SYNCTHING INFO] $1${NC}"
}

# Load Tailscale info
if [[ -f /tmp/tailscale_info ]]; then
    source /tmp/tailscale_info
fi

# Create syncthing directories
log "Création des répertoires Syncthing..."
mkdir -p /opt/syncthing/{config,data/obsidian-notes}
chown -R 1000:1000 /opt/syncthing

# Generate docker-compose.yml if not exists
if [[ ! -f docker-compose.yml ]]; then
    log "Génération de docker-compose.yml..."
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  syncthing:
    image: syncthing/syncthing:latest
    container_name: syncthing
    hostname: ${SYNCTHING_HOSTNAME:-syncthing}
    environment:
      - PUID=1000
      - PGID=1000
      - UMASK=022
    volumes:
      - /opt/syncthing/config:/var/syncthing/config
      - /opt/syncthing/data:/var/syncthing/data
    ports:
      - "8384:8384"    # Web UI
      - "22000:22000/tcp"  # TCP file transfers
      - "22000:22000/udp"  # QUIC file transfers
      - "21027:21027/udp"  # Receive local discovery broadcasts
    restart: unless-stopped
    networks:
      - syncthing_net
    mem_limit: 256m
    cpus: 0.5

networks:
  syncthing_net:
    driver: bridge
EOF
fi

# Start Syncthing
log "Démarrage de Syncthing..."
docker-compose up -d

# Wait for Syncthing to start
log "Attente du démarrage de Syncthing..."
sleep 10

# Verify Syncthing is running
if ! docker ps | grep -q syncthing; then
    error "Syncthing n'a pas pu démarrer"
fi

# Wait for config file to be generated
while [[ ! -f /opt/syncthing/config/config.xml ]]; do
    info "Attente de la génération du fichier de configuration..."
    sleep 2
done

log "Arrêt temporaire pour configuration..."
docker-compose stop

# Configure Syncthing
log "Configuration de Syncthing..."

# Backup original config
cp /opt/syncthing/config/config.xml /opt/syncthing/config/config.xml.backup

# Configure API and GUI
python3 << 'EOF'
import xml.etree.ElementTree as ET
import os

config_file = '/opt/syncthing/config/config.xml'
tree = ET.parse(config_file)
root = tree.getroot()

# Configure GUI to listen on all interfaces (Tailscale)
gui = root.find('gui')
if gui is not None:
    gui.set('enabled', 'true')
    gui.set('tls', 'false')
    
    address = gui.find('address')
    if address is not None:
        address.text = '0.0.0.0:8384'
    
    # Remove authentication for initial setup (will be secured by Tailscale)
    user = gui.find('user')
    password = gui.find('password')
    if user is not None:
        user.text = ''
    if password is not None:
        password.text = ''

# Add default folder for Obsidian notes
folders = root.find('folders')
if folders is not None:
    # Check if folder already exists
    obsidian_folder = None
    for folder in folders.findall('folder'):
        if folder.get('id') == 'obsidian-notes':
            obsidian_folder = folder
            break
    
    if obsidian_folder is None:
        obsidian_folder = ET.SubElement(folders, 'folder')
        obsidian_folder.set('id', 'obsidian-notes')
        obsidian_folder.set('label', 'Obsidian Notes')
        obsidian_folder.set('path', '/var/syncthing/data/obsidian-notes')
        obsidian_folder.set('type', 'sendreceive')
        obsidian_folder.set('rescanIntervalS', '3600')
        obsidian_folder.set('fsWatcherEnabled', 'true')
        obsidian_folder.set('fsWatcherDelayS', '10')

# Save configuration
tree.write(config_file, encoding='utf-8', xml_declaration=True)
print("Configuration Syncthing mise à jour")
EOF

log "Redémarrage de Syncthing avec la nouvelle configuration..."
docker-compose up -d

# Wait for startup
sleep 10

# Get Device ID
log "Récupération du Device ID..."
DEVICE_ID=""
for i in {1..30}; do
    if DEVICE_ID=$(curl -s -X GET "http://localhost:8384/rest/system/status" | jq -r '.myID' 2>/dev/null); then
        if [[ "$DEVICE_ID" != "null" && -n "$DEVICE_ID" ]]; then
            break
        fi
    fi
    sleep 2
done

if [[ -z "$DEVICE_ID" || "$DEVICE_ID" == "null" ]]; then
    error "Impossible de récupérer le Device ID"
fi

log "Device ID Syncthing: ${DEVICE_ID}"

# Save device info for other scripts
echo "SYNCTHING_DEVICE_ID=${DEVICE_ID}" >> /tmp/syncthing_info
echo "SYNCTHING_WEB_URL=http://localhost:8384" >> /tmp/syncthing_info

log "Syncthing installé et configuré avec succès ✅"
info "Dossier de synchronisation: /opt/syncthing/data/obsidian-notes"
info "Interface Web: http://localhost:8384 (accessible via Tailscale)"
