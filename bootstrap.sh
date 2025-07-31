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
    log "Variables d'environnement chargées depuis .env ✅"
else
    error "Fichier .env non trouvé. Copiez .env.example vers .env et configurez-le."
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
    fi
    
    if [[ -z "${DOMAIN_ROOT:-}" ]]; then
        read -p "Domaine racine [ori3com.cloud]: " DOMAIN_ROOT
        DOMAIN_ROOT=${DOMAIN_ROOT:-ori3com.cloud}
    fi
    
    if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
        read -p "Tailscale Auth Key: " TAILSCALE_AUTH_KEY
    fi
    
    if [[ -z "${HOSTNAME_SUFFIX:-}" ]]; then
        read -p "Suffixe hostname [01]: " HOSTNAME_SUFFIX
        HOSTNAME_SUFFIX=${HOSTNAME_SUFFIX:-01}
    fi
    
    if [[ -z "${ENABLE_CADDY:-}" ]]; then
        echo
        info "Caddy Reverse Proxy avec SSL automatique ?"
        info "- OUI: Certificats SSL valides automatiques"
        info "- NON: HTTPS Syncthing intégré (certificat auto-signé)"
        read -p "Activer Caddy ? [y/N]: " caddy_choice
        if [[ "$caddy_choice" =~ ^[Yy]$ ]]; then
            ENABLE_CADDY="true"
        else
            ENABLE_CADDY="false"
        fi
    fi
}

# Validation et export des variables requises
setup_environment() {
    local required_vars=(
        "CF_API_TOKEN"
        "DOMAIN_ROOT"
        "TAILSCALE_AUTH_KEY"
        "HOSTNAME_SUFFIX"
    )
    
    log "Validation et export des variables d'environnement..."
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Variable requise manquante: $var. Vérifiez votre fichier .env"
        else
            log "✓ $var configuré"
            export "$var"  # Export explicite
        fi
    done
    
    # Générer et exporter les variables dérivées
    export SERVER_NAME="vpn-syncthing-${HOSTNAME_SUFFIX}"
    export SYNCTHING_HOSTNAME="syncthing-${HOSTNAME_SUFFIX}"
    
    # Configuration Caddy
    export ENABLE_CADDY="${ENABLE_CADDY:-false}"
    
    log "Variables exportées:"
    info "  - SERVER_NAME: $SERVER_NAME"
    info "  - SYNCTHING_HOSTNAME: $SYNCTHING_HOSTNAME"
    info "  - ENABLE_CADDY: $ENABLE_CADDY"
    info "  - TAILSCALE_AUTH_KEY: ${TAILSCALE_AUTH_KEY:0:20}..."
    
    log "Configuration validée et variables exportées ✅"
}

# Check system requirements
check_requirements() {
    info "Vérification des prérequis système..."
    
    # Detect and display architecture
    local arch=$(uname -m)
    local arch_name=""
    local arch_optimized=false
    
    case "$arch" in
        "x86_64")
            arch_name="x86_64 (AMD64)"
            arch_optimized=true
            ;;
        "aarch64")
            arch_name="ARM64 (AArch64)" 
            arch_optimized=true
            ;;
        "armv7l")
            arch_name="ARM32 (ARMv7)"
            arch_optimized=false
            warn "Architecture ARM32 détectée - Performance limitée recommandée"
            ;;
        "i386"|"i686")
            arch_name="x86 32-bit"
            arch_optimized=false
            warn "Architecture 32-bit détectée - Considérez un upgrade vers 64-bit"
            ;;
        *)
            arch_name="$arch (Non testé)"
            arch_optimized=false
            warn "Architecture non testée: $arch"
            ;;
    esac
    
    log "Architecture détectée: $arch_name"
    export DETECTED_ARCH="$arch"
    export ARCH_OPTIMIZED="$arch_optimized"
    
    # Architecture-specific optimizations
    if [[ "$arch_optimized" == "true" ]]; then
        log "✅ Architecture optimisée pour ce déploiement"
    else
        warn "⚠️  Architecture non optimisée - Performance réduite possible"
    fi
    
    # Check available memory with architecture-specific recommendations
    local mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    local mem_total_mb=$((mem_total / 1024))
    local min_mem_recommended=512
    
    # Adjust memory requirements based on architecture
    case "$arch" in
        "x86_64")
            min_mem_recommended=512
            ;;
        "aarch64")
            min_mem_recommended=512
            ;;
        "armv7l")
            min_mem_recommended=256
            warn "ARM32: Limites mémoire réduites appliquées"
            ;;
        "i386"|"i686")
            min_mem_recommended=256
            warn "32-bit: Limites mémoire réduites appliquées"
            ;;
    esac
    
    if [[ $mem_total_mb -lt $min_mem_recommended ]]; then
        warn "RAM disponible: ${mem_total_mb}MB (recommandé: ≥${min_mem_recommended}MB pour $arch_name)"
        
        # Architecture-specific memory warnings
        if [[ "$arch" == "x86_64" ]] && [[ $mem_total_mb -lt 512 ]]; then
            warn "x86_64 avec <512MB RAM peut causer des problèmes de performance"
        elif [[ "$arch" == "aarch64" ]] && [[ $mem_total_mb -lt 512 ]]; then
            warn "ARM64 avec <512MB RAM peut limiter les fonctionnalités"
        fi
    else
        log "RAM disponible: ${mem_total_mb}MB ✅"
    fi
    
    # Check CPU cores with architecture-specific info
    local cpu_cores=$(nproc)
    log "CPU cores détectés: $cpu_cores"
    
    # Architecture-specific CPU info
    case "$arch" in
        "x86_64")
            local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
            info "CPU x86_64: ${cpu_model:-Non identifié}"
            ;;
        "aarch64")
            local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs || echo "ARM64 Generic")
            info "CPU ARM64: ${cpu_model}"
            ;;
    esac
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error "Pas de connectivité internet"
    fi
    
    # Check if running in container/VM
    if [[ -f /.dockerenv ]]; then
        warn "Exécution dans un container Docker détectée"
    elif grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
        info "Exécution dans une VM détectée"
    fi
    
    log "Prérequis système validés pour $arch_name ✅"
}

# Update system
update_system() {
    log "Mise à jour du système..."
    
    # Detect package manager and architecture
    local pkg_manager=""
    local install_cmd=""
    
    if command -v apt-get >/dev/null; then
        pkg_manager="apt"
        install_cmd="apt-get install -y"
        apt-get update >/dev/null 2>&1
    elif command -v yum >/dev/null; then
        pkg_manager="yum"
        install_cmd="yum install -y"
        yum update -y >/dev/null 2>&1
    elif command -v dnf >/dev/null; then
        pkg_manager="dnf"  
        install_cmd="dnf install -y"
        dnf update -y >/dev/null 2>&1
    elif command -v pacman >/dev/null; then
        pkg_manager="pacman"
        install_cmd="pacman -S --noconfirm"
        pacman -Sy >/dev/null 2>&1
    else
        error "Gestionnaire de paquets non supporté"
    fi
    
    log "Gestionnaire de paquets détecté: $pkg_manager"
    
    # Install packages based on package manager
    case "$pkg_manager" in
        "apt")
            $install_cmd curl wget jq git docker-compose-v2 iputils-ping >/dev/null 2>&1
            ;;
        "yum"|"dnf")
            $install_cmd curl wget jq git docker-compose-v2 iputils-ping >/dev/null 2>&1
            ;;
        "pacman")
            $install_cmd curl wget jq git docker-compose-v2 iputils-ping >/dev/null 2>&1
            ;;
    esac
    
    # Start Docker with architecture-specific optimizations
    systemctl enable docker >/dev/null 2>&1
    systemctl start docker >/dev/null 2>&1
    
    # Architecture-specific Docker optimizations
    local docker_opts=""
    case "${DETECTED_ARCH:-}" in
        "aarch64")
            # ARM64 optimizations
            docker_opts="--default-ulimit nofile=1024:4096"
            ;;
        "x86_64")
            # x86_64 optimizations  
            docker_opts="--default-ulimit nofile=2048:8192"
            ;;
        *)
            # Conservative defaults for other architectures
            docker_opts="--default-ulimit nofile=1024:2048"
            ;;
    esac
    
    # Apply Docker daemon configuration if needed
    if [[ ! -f /etc/docker/daemon.json ]]; then
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
        systemctl restart docker >/dev/null 2>&1
        sleep 3
    fi
    
    log "Système mis à jour pour ${DETECTED_ARCH:-unknown} ✅"
}

# Wrapper pour lancer les scripts avec les bonnes variables
run_script() {
    local script_name="$1"
    local script_path="scripts/$script_name"
    
    if [[ ! -f "$script_path" ]]; then
        error "Script non trouvé: $script_path"
    fi
    
    log "Exécution de $script_name..."
    
    # Vérification que les variables sont bien exportées
    if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
        error "TAILSCALE_AUTH_KEY non exporté avant lancement de $script_name"
    fi
    
    # Lancement du script avec env explicite pour être sûr
    env \
        CF_API_TOKEN="$CF_API_TOKEN" \
        DOMAIN_ROOT="$DOMAIN_ROOT" \
        TAILSCALE_AUTH_KEY="$TAILSCALE_AUTH_KEY" \
        HOSTNAME_SUFFIX="$HOSTNAME_SUFFIX" \
        SERVER_NAME="$SERVER_NAME" \
        SYNCTHING_HOSTNAME="$SYNCTHING_HOSTNAME" \
        ENABLE_CADDY="$ENABLE_CADDY" \
        bash "$script_path"
}

# Main execution
main() {
    log "🚀 Démarrage du déploiement Syncthing + Tailscale"
    
    check_requirements
    configure_interactively
    setup_environment
    update_system
    
    # Lancement des scripts avec les variables exportées
    run_script "install_tailscale.sh"
    run_script "install_syncthing.sh"
    
    # Installation optionnelle de Caddy
    if [[ "${ENABLE_CADDY:-false}" == "true" ]]; then
        log "Installation de Caddy (reverse proxy SSL)..."
        run_script "install_caddy.sh"
    else
        log "Caddy désactivé - Utilisation de HTTPS Syncthing intégré"
    fi
    
    run_script "cf_dns_register.sh"
    run_script "verify_setup.sh"
    
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
