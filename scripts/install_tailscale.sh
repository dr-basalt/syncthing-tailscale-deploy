#!/bin/bash
set -euo pipefail

# 🔐 Tailscale Installation Script for ARM64

# Source environment if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../.env" ]]; then
    source "$SCRIPT_DIR/../.env"
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[TAILSCALE] $1${NC}"
}

error() {
    echo -e "${RED}[TAILSCALE ERROR] $1${NC}"
    exit 1
}

# Check if already installed
if command -v tailscale >/dev/null; then
    if tailscale status >/dev/null 2>&1; then
        log "Tailscale déjà installé et connecté ✅"
        exit 0
    fi
fi

log "Installation de Tailscale..."

# Download and install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Verify installation
if ! command -v tailscale >/dev/null; then
    error "Échec de l'installation de Tailscale"
fi

log "Tailscale installé ✅"

# Configure Tailscale
if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
    error "TAILSCALE_AUTH_KEY non défini. Vérifiez votre fichier .env ou relancez en mode interactif"
fi

if [[ -z "${SERVER_NAME:-}" ]]; then
    error "SERVER_NAME non défini. Vérifiez la configuration"
fi

log "Connexion à Tailscale avec hostname: ${SERVER_NAME}"

# Tailscale up with auth key and hostname
tailscale up \
    --authkey="${TAILSCALE_AUTH_KEY}" \
    --hostname="${SERVER_NAME}" \
    --accept-routes \
    --accept-dns=false

# Wait for connection
sleep 5

# Verify connection
if ! tailscale status >/dev/null 2>&1; then
    error "Échec de la connexion Tailscale"
fi

# Get Tailscale IP
TAILSCALE_IP=$(tailscale ip -4)
log "Adresse Tailscale IP: ${TAILSCALE_IP}"

# Export for other scripts
echo "TAILSCALE_IP=${TAILSCALE_IP}" >> /tmp/tailscale_info

log "Tailscale configuré avec succès ✅"
