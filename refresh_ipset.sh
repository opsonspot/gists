#!/bin/sh

IPSET_NAME="outb_usa"
LOG_FILE="/var/log/refresh_ipset.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Function to check if IP is valid IPv4
is_valid_ipv4() {
    echo "$1" | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' > /dev/null
}

# Function to resolve domain and add IPs
resolve_and_add_domain() {
    domain=$1
    resolved_ips=""
    count=0
    
    # Try to resolve the domain
    resolved_ips=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || true)
    
    if [ -z "$resolved_ips" ]; then
        log "WARNING: Could not resolve domain $domain to any IPv4 addresses"
        return 1
    fi
    
    for ip in $resolved_ips; do
        if is_valid_ipv4 "$ip"; then
            log "Adding IP $ip for domain $domain"
            if ipset add -exist "$TEMP_IPSET" "$ip" 2>&1 | grep -v "already added" | grep -E "(error|Error)" > /dev/null; then
                log "ERROR: Failed to add IP $ip for domain $domain"
            else
                count=$(expr $count + 1)
            fi
        else
            log "WARNING: Invalid IP format '$ip' for domain $domain"
        fi
    done
    
    if [ $count -eq 0 ]; then
        log "WARNING: No valid IPs added for domain $domain"
        return 1
    fi
    
    return 0
}

# Start of script
log "Starting IPSet refresh for $IPSET_NAME"

# Check if the IPSet exists, if not, create it
if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
    log "Creating IPSet $IPSET_NAME"
    ipset create "$IPSET_NAME" hash:net family inet hashsize 1024 maxelem 65536
else
    log "IPSet $IPSET_NAME already exists"
fi

# Create a temporary IPSet for atomic swap
TEMP_IPSET="${IPSET_NAME}_temp"
if ipset list "$TEMP_IPSET" >/dev/null 2>&1; then
    ipset destroy "$TEMP_IPSET"
fi
ipset create "$TEMP_IPSET" hash:net family inet hashsize 1024 maxelem 65536

# Static IPs
STATIC_IPS="
10.1.0.0/16
10.2.0.0/16
10.3.0.0/16
10.100.0.0/16
20.0.0.0/16
"

# Domains
DOMAINS="
okta.com
whatismyipaddress.com
microsoft.com
microsoftonline.com
office.com
namecheap.com
aliexpress.com
slack.com
pingone.com
mskcc.org
myworkday.com
docusign.com
ssofed.mskcc.org
msktime.mskcc.org
authenticator.pingone.com
thespot.mskcc.org
workday.mskcc.org
www.myworkday.com
hcm.paycor.com
"

# Counter for successful operations
static_count=0
domain_count=0
failed_domains=""

# Add static IPs to temporary set
log "Adding static IPs..."
for ip in $STATIC_IPS; do
    if [ -n "$ip" ] && [ "$ip" != "" ]; then
        log "Adding static IP/subnet: $ip"
        if ipset add -exist "$TEMP_IPSET" "$ip" 2>&1 | grep -v "already added" | grep -E "(error|Error)" > /dev/null; then
            log "ERROR: Failed to add static IP/subnet $ip"
        else
            static_count=$(expr $static_count + 1)
        fi
    fi
done

log "Successfully added $static_count static IP/subnet entries"

# Add resolved IPs to temporary set
log "Resolving and adding domain IPs..."
for domain in $DOMAINS; do
    if [ -n "$domain" ] && [ "$domain" != "" ]; then
        if resolve_and_add_domain "$domain"; then
            domain_count=$(expr $domain_count + 1)
        else
            failed_domains="$failed_domains $domain"
        fi
    fi
done

log "Successfully resolved $domain_count domains"

if [ -n "$failed_domains" ]; then
    log "WARNING: Failed to resolve the following domains:$failed_domains"
fi

# Swap the IPSets atomically
log "Swapping IPSets..."
if ipset swap "$TEMP_IPSET" "$IPSET_NAME"; then
    log "Successfully swapped IPSets"
    ipset destroy "$TEMP_IPSET"
else
    log "ERROR: Failed to swap IPSets"
    ipset destroy "$TEMP_IPSET"
    exit 1
fi

# Save the IPSet configuration
log "Saving IPSet configuration..."
if command -v ipset-save >/dev/null 2>&1; then
    ipset-save > /etc/ipset.conf 2>/dev/null || log "WARNING: Could not save to /etc/ipset.conf"
else
    ipset save > /etc/ipset.conf 2>/dev/null || log "WARNING: Could not save to /etc/ipset.conf"
fi

# Final statistics
total_entries=$(ipset list "$IPSET_NAME" | grep -c "^[0-9]" || echo "0")
log "IPSet refresh completed. Total entries in $IPSET_NAME: $total_entries"
log "Summary: $static_count static entries, $domain_count domains resolved successfully"

exit 0
