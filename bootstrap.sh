#!/bin/bash
set -euo pipefail

# 🚀 Bootstrap Script - Syncthing + Tailscale VPS ARM64
# Usage: ./bootstrap.sh [--auto]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "Ce script doit être exécuté en tant que root (sudo)"
fi

# Load environment variables
if [[ -f .env ]]; then
    source .env
    log "Variables d'environnement chargées depuis .env"
else
    warn "Fichier .env non trouvé"
fi

# Interactive mode if --auto not specified
AUTO_MODE=false
if [[ "${1:-}" == "--auto" ]]; then
    AUTO_MODE=true
    log "Mode automatique activé"
else
    log "Mode interactif activé"
fi

# Interactive configuration
configure_interactively() {
    if [[ $AUTO_MODE == "true" ]]; then
        return
    fi

    echo
    info "=== Configuration Interactive ==="
    
    if [[ -z "${CF_API_TOKEN:-}" ]]; then
        read -p "Cloudflare API Token: " CF_API_TOKEN
        export CF_API_TOKEN
    fi
    
    if [[ -z "${CF_ZONE_ID:-}" ]]; then
        read -p "Cloudflare Zone ID: " CF_ZONE_ID
        export CF_ZONE_ID
    fi
    
    if [[ -z "${DOMAIN_ROOT:-}" ]]; then
        read -p "Domaine racine [ori3com.cloud]: " DOMAIN_ROOT
        DOMAIN_ROOT=${DOMAIN_ROOT:-ori3com.cloud}
        export DOMAIN_ROOT
    fi
    
    if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
        read -p "Tailscale Auth Key: " TAILSCALE_AUTH_KEY
        export TAILSCALE_AUTH_KEY
    fi
    
    if [[ -z "${HOSTNAME_SUFFIX:-}" ]]; then
        read -p "Suffixe hostname [01]: " HOSTNAME_SUFFIX
        HOSTNAME_SUFFIX=${HOSTNAME_SUFFIX:-01}
        export HOSTNAME_SUFFIX
    fi
}

# Validation des variables requises
validate_config() {
    local required_vars=(
        "CF_API_TOKEN"
        "CF_ZONE_ID" 
        "DOMAIN_ROOT"
        "TAILSCALE_AUTH_KEY"
        "HOSTNAME_SUFFIX"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Variable requise manquante: $var"
        fi
    done
    
    log "Configuration validée ✅"
}

# Check system requirements
check_requirements() {
    info "Vérification des prérequis système..."
    
    # Check ARM64
    if [[ $(uname -m) != "aarch64" ]]; then
        warn "Architecture non-ARM64 détectée: $(uname -m)"
    fi
    
    # Check available memory
    local mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    local mem_total_mb=$((mem_total / 1024))
    
    if [[ $mem_total_mb -lt 512 ]]; then
        warn "RAM disponible: ${mem_total_mb}MB (recommandé: ≥512MB)"
    else
        log "RAM disponible: ${mem_total_mb}MB ✅"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error "Pas de connectivité internet"
    fi
    
    log "Prérequis système validés ✅"
}

# Update system
update_system() {
    log "Mise à jour du système..."
    
    if command -v apt-get >/dev/null; then
        apt-get update >/dev/null 2>&1
        apt-get install -y curl wget jq git docker.io docker-compose >/dev/null 2>&1
    elif command -v yum >/dev/null; then
        yum update -y >/dev/null 2>&1
        yum install -y curl wget jq git docker docker-compose >/dev/null 2>&1
    else
        error "Gestionnaire de paquets non supporté"
    fi
    
    # Start Docker
    systemctl enable docker >/dev/null 2>&1
    systemctl start docker >/dev/null 2>&1
    
    log "Système mis à jour ✅"
}

# Main execution
main() {
    log "🚀 Démarrage du déploiement Syncthing + Tailscale"
    
    check_requirements
    configure_interactively
    validate_config
    update_system
    
    # Export variables for sub-scripts
    export SERVER_NAME="vpn-syncthing-${HOSTNAME_SUFFIX}"
    export SYNCTHING_HOSTNAME="syncthing-${HOSTNAME_SUFFIX}"
    
    log "Installation de Tailscale..."
    bash scripts/install_tailscale.sh
    
    log "Installation de Syncthing..."
    bash scripts/install_syncthing.sh
    
    log "Configuration DNS Cloudflare..."
    bash scripts/cf_dns_register.sh
    
    log "Vérification du déploiement..."
    bash scripts/verify_setup.sh
    
    echo
    log "🎉 Déploiement terminé avec succès!"
    echo
    info "=== Informations d'accès ==="
    info "Syncthing Web UI: http://${SYNCTHING_HOSTNAME}.${DOMAIN_ROOT}:8384"
    info "Accessible uniquement via Tailscale VPN"
    echo
    info "Pour configurer un client mobile:"
    info "1. Installez Tailscale sur votre appareil"
    info "2. Connectez-vous au même réseau Tailscale" 
    info "3. Utilisez l'adresse Tailscale du serveur"
    echo
}

# Execute main function
main "$@"
