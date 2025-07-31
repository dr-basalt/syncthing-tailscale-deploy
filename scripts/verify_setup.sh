#!/bin/bash
set -euo pipefail

# 🔍 Setup Verification Script

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[VERIFY] $1${NC}"
}

error() {
    echo -e "${RED}[VERIFY ERROR] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[VERIFY WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[VERIFY INFO] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

fail() {
    echo -e "${RED}❌ $1${NC}"
}

# Load info files
load_info() {
    if [[ -f /tmp/tailscale_info ]]; then
        source /tmp/tailscale_info
    fi
    
    if [[ -f /tmp/syncthing_info ]]; then
        source /tmp/syncthing_info
    fi
    
    if [[ -f /tmp/dns_info ]]; then
        source /tmp/dns_info
    fi
}

# Test functions
test_tailscale() {
    log "Test Tailscale..."
    
    if ! command -v tailscale >/dev/null; then
        fail "Tailscale non installé"
        return 1
    fi
    
    if ! tailscale status >/dev/null 2>&1; then
        fail "Tailscale non connecté"
        return 1
    fi
    
    local ts_ip=$(tailscale ip -4 2>/dev/null || echo "")
    if [[ -n "$ts_ip" ]]; then
        success "Tailscale connecté (IP: $ts_ip)"
        return 0
    else
        fail "Impossible de récupérer l'IP Tailscale"
        return 1
    fi
}

test_docker() {
    log "Test Docker..."
    
    if ! command -v docker >/dev/null; then
        fail "Docker non installé"
        return 1
    fi
    
    if ! docker ps >/dev/null 2>&1; then
        fail "Docker non accessible"
        return 1
    fi
    
    success "Docker opérationnel"
    return 0
}

test_syncthing() {
    log "Test Syncthing..."
    
    if ! docker ps | grep -q syncthing; then
        fail "Container Syncthing non en cours d'exécution"
        return 1
    fi
    
    # Test simple : vérifier que le container est healthy
    local container_status=$(docker inspect syncthing --format='{{.State.Health.Status}}' 2>/dev/null || echo "")
    if [[ "$container_status" == "healthy" ]]; then
        success "Syncthing container healthy"
    else
        warn "Syncthing container status: $container_status"
    fi
    
    # Test interface web (sans API pour éviter CSRF)
    local web_test_count=0
    while [[ $web_test_count -lt 5 ]]; do
        if curl -s -f "http://localhost:8384/" >/dev/null 2>&1; then
            success "Syncthing Web UI accessible"
            break
        fi
        sleep 2
        ((web_test_count++))
    done
    
    if [[ $web_test_count -eq 5 ]]; then
        fail "Syncthing Web UI non accessible"
        return 1
    fi
    
    # Test folder existence
    if [[ -d "/opt/syncthing/data/obsidian-notes" ]]; then
        success "Dossier Obsidian Notes configuré"
    else
        warn "Dossier Obsidian Notes non trouvé"
    fi
    
    return 0
}

test_dns() {
    log "Test DNS..."
    
    if [[ -z "${VPN_HOSTNAME:-}" ]]; then
        warn "Informations DNS non disponibles"
        return 1
    fi
    
    # Test individual hostname
    if dig +short "$VPN_HOSTNAME" | grep -q "${TAILSCALE_IP:-}"; then
        success "DNS individuel résolu: $VPN_HOSTNAME"
    else
        fail "DNS individuel non résolu: $VPN_HOSTNAME"
    fi
    
    # Test round-robin (at least check if it resolves)
    if [[ -n "${RR_VPN_HOSTNAME:-}" ]]; then
        if dig +short "$RR_VPN_HOSTNAME" | grep -q .; then
            success "DNS Round-Robin résolu: $RR_VPN_HOSTNAME"
        else
            fail "DNS Round-Robin non résolu: $RR_VPN_HOSTNAME"
        fi
    fi
    
    return 0
}

test_connectivity() {
    log "Test de connectivité..."
    
    # Test internet
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        success "Connectivité internet OK"
    else
        fail "Pas de connectivité internet"
    fi
    
    # Test local services
    if curl -s -f "http://localhost:8384/rest/system/ping" >/dev/null 2>&1; then
        success "Syncthing Web UI accessible localement"
    else
        fail "Syncthing Web UI non accessible"
    fi
    
    return 0
}

display_summary() {
    echo
    log "=== RÉSUMÉ DE LA CONFIGURATION ==="
    echo
    
    if [[ -n "${TAILSCALE_IP:-}" ]]; then
        info "🔐 Tailscale IP: $TAILSCALE_IP"
    fi
    
    if [[ -n "${SYNCTHING_DEVICE_ID:-}" ]]; then
        info "📱 Device ID Syncthing: $SYNCTHING_DEVICE_ID"
    fi
    
    if [[ -n "${VPN_HOSTNAME:-}" ]]; then
        info "🌐 Hostname VPN: $VPN_HOSTNAME"
    fi
    
    if [[ -n "${SYNCTHING_HOSTNAME:-}" ]]; then
        info "🔄 Hostname Syncthing: $SYNCTHING_HOSTNAME"
    fi
    
    echo
    info "📁 Dossier de synchronisation: /opt/syncthing/data/obsidian-notes"
    info "🖥️  Interface Web: http://localhost:8384"
    info "📱 Accessible via Tailscale depuis mobile/desktop"
    
    echo
    log "=== ÉTAPES SUIVANTES ==="
    info "1. Installer Tailscale sur vos appareils clients"
    info "2. Se connecter au même réseau Tailscale"
    info "3. Installer Syncthing sur les appareils clients"
    info "4. Ajouter ce serveur comme device dans Syncthing clients"
    info "   Device ID: ${SYNCTHING_DEVICE_ID:-'Non disponible'}"
    echo
}

# Main verification
main() {
    log "🔍 Vérification de l'installation Syncthing + Tailscale"
    echo
    
    load_info
    
    local test_results=()
    
    test_tailscale && test_results+=("tailscale:OK") || test_results+=("tailscale:FAIL")
    test_docker && test_results+=("docker:OK") || test_results+=("docker:FAIL")
    test_syncthing && test_results+=("syncthing:OK") || test_results+=("syncthing:FAIL")
    test_dns && test_results+=("dns:OK") || test_results+=("dns:FAIL")
    test_connectivity && test_results+=("connectivity:OK") || test_results+=("connectivity:FAIL")
    
    echo
    log "=== RÉSULTATS DES TESTS ==="
    
    local failed_tests=0
    for result in "${test_results[@]}"; do
        local test_name=$(echo "$result" | cut -d: -f1)
        local test_status=$(echo "$result" | cut -d: -f2)
        
        if [[ "$test_status" == "OK" ]]; then
            success "$test_name"
        else
            fail "$test_name"
            ((failed_tests++))
        fi
    done
    
    echo
    if [[ $failed_tests -eq 0 ]]; then
        log "🎉 Tous les tests sont passés avec succès!"
        display_summary
        exit 0
    else
        error "$failed_tests test(s) ont échoué"
        echo
        warn "Consultez les logs ci-dessus pour résoudre les problèmes"
        exit 1
    fi
}

# Execute main function
main
