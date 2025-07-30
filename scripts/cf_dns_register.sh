#!/bin/bash
set -euo pipefail

# 🌐 Cloudflare DNS Registration Script

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[CLOUDFLARE] $1${NC}"
}

error() {
    echo -e "${RED}[CLOUDFLARE ERROR] $1${NC}"
    exit 1
}

warn() {
    echo -e "${YELLOW}[CLOUDFLARE WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[CLOUDFLARE INFO] $1${NC}"
}

# Load Tailscale info
if [[ -f /tmp/tailscale_info ]]; then
    source /tmp/tailscale_info
fi

# Validate required variables
if [[ -z "${CF_API_TOKEN:-}" ]]; then
    error "CF_API_TOKEN non défini"
fi

if [[ -z "${CF_ZONE_ID:-}" ]]; then
    error "CF_ZONE_ID non défini"
fi

if [[ -z "${DOMAIN_ROOT:-}" ]]; then
    error "DOMAIN_ROOT non défini"
fi

if [[ -z "${TAILSCALE_IP:-}" ]]; then
    error "TAILSCALE_IP non défini (Tailscale non configuré?)"
fi

if [[ -z "${HOSTNAME_SUFFIX:-}" ]]; then
    error "HOSTNAME_SUFFIX non défini"
fi

# Cloudflare API headers
CF_HEADERS=(
    "Authorization: Bearer ${CF_API_TOKEN}"
    "Content-Type: application/json"
)

# Function to make Cloudflare API calls
cf_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local url="https://api.cloudflare.com/v4/zones/${CF_ZONE_ID}/dns_records${endpoint}"
    
    if [[ -n "$data" ]]; then
        curl -s -X "$method" "$url" \
            "${CF_HEADERS[@]/#/-H }" \
            -d "$data"
    else
        curl -s -X "$method" "$url" \
            "${CF_HEADERS[@]/#/-H }"
    fi
}

# Function to get existing DNS record
get_dns_record() {
    local name="$1"
    cf_api "GET" "?type=A&name=${name}"
}

# Function to create or update DNS record
upsert_dns_record() {
    local name="$1"
    local ip="$2"
    local ttl="${3:-300}"
    
    log "Configuration DNS pour ${name} -> ${ip}"
    
    # Check if record exists
    local response=$(get_dns_record "$name")
    local record_id=$(echo "$response" | jq -r '.result[0].id // empty')
    
    local data=$(jq -n \
        --arg name "$name" \
        --arg ip "$ip" \
        --arg ttl "$ttl" \
        '{
            type: "A",
            name: $name,
            content: $ip,
            ttl: ($ttl | tonumber),
            proxied: false
        }')
    
    if [[ -n "$record_id" && "$record_id" != "null" ]]; then
        # Update existing record
        log "Mise à jour de l'enregistrement existant: ${name}"
        local update_response=$(cf_api "PUT" "/${record_id}" "$data")
        
        if echo "$update_response" | jq -e '.success' >/dev/null; then
            log "✅ Enregistrement mis à jour: ${name} -> ${ip}"
        else
            error "Échec de la mise à jour: $(echo "$update_response" | jq -r '.errors[0].message // "Erreur inconnue"')"
        fi
    else
        # Create new record
        log "Création d'un nouvel enregistrement: ${name}"
        local create_response=$(cf_api "POST" "" "$data")
        
        if echo "$create_response" | jq -e '.success' >/dev/null; then
            log "✅ Enregistrement créé: ${name} -> ${ip}"
        else
            error "Échec de la création: $(echo "$create_response" | jq -r '.errors[0].message // "Erreur inconnue"')"
        fi
    fi
}

# Main DNS configuration
main() {
    log "Configuration DNS Cloudflare pour ${DOMAIN_ROOT}"
    
    # Individual server records
    local vpn_hostname="vpn-syncthing-${HOSTNAME_SUFFIX}.${DOMAIN_ROOT}"
    local syncthing_hostname="syncthing-${HOSTNAME_SUFFIX}.${DOMAIN_ROOT}"
    
    # Create individual records
    upsert_dns_record "$vpn_hostname" "$TAILSCALE_IP"
    upsert_dns_record "$syncthing_hostname" "$TAILSCALE_IP"
    
    # Round-robin records
    local rr_vpn="vpn-syncthing.${DOMAIN_ROOT}"
    local rr_syncthing="syncthing.${DOMAIN_ROOT}"
    
    # For round-robin, we need to check existing records and add ours
    log "Configuration Round-Robin pour ${rr_vpn}"
    
    # Get existing round-robin records
    local existing_rr_response=$(get_dns_record "$rr_vpn")
    local existing_ips=$(echo "$existing_rr_response" | jq -r '.result[].content')
    
    # Check if our IP is already in round-robin
    if echo "$existing_ips" | grep -q "$TAILSCALE_IP"; then
        log "IP ${TAILSCALE_IP} déjà présente dans le round-robin ${rr_vpn}"
    else
        log "Ajout de ${TAILSCALE_IP} au round-robin ${rr_vpn}"
        upsert_dns_record "$rr_vpn" "$TAILSCALE_IP" 60
    fi
    
    # Same for syncthing round-robin
    log "Configuration Round-Robin pour ${rr_syncthing}"
    existing_rr_response=$(get_dns_record "$rr_syncthing")
    existing_ips=$(echo "$existing_rr_response" | jq -r '.result[].content')
    
    if echo "$existing_ips" | grep -q "$TAILSCALE_IP"; then
        log "IP ${TAILSCALE_IP} déjà présente dans le round-robin ${rr_syncthing}"
    else
        log "Ajout de ${TAILSCALE_IP} au round-robin ${rr_syncthing}"
        upsert_dns_record "$rr_syncthing" "$TAILSCALE_IP" 60
    fi
    
    # Save DNS info
    cat > /tmp/dns_info << EOF
VPN_HOSTNAME=${vpn_hostname}
SYNCTHING_HOSTNAME=${syncthing_hostname}
RR_VPN_HOSTNAME=${rr_vpn}
RR_SYNCTHING_HOSTNAME=${rr_syncthing}
EOF
    
    log "Configuration DNS terminée ✅"
    
    echo
    info "=== Enregistrements DNS configurés ==="
    info "Serveur individuel:"
    info "  - ${vpn_hostname} -> ${TAILSCALE_IP}"
    info "  - ${syncthing_hostname} -> ${TAILSCALE_IP}"
    info "Round-Robin:"
    info "  - ${rr_vpn}"
    info "  - ${rr_syncthing}"
    echo
}

# Execute main function
main
