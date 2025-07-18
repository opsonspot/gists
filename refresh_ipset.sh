#!/bin/sh

IPSET_NAME="outb_usa"

# Check if the IPSet exists, if not, create it
if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
  ipset create "$IPSET_NAME" hash:net family inet hashsize 1024 maxelem 65536
fi

# Flush existing entries
ipset flush "$IPSET_NAME"

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
"

# Add static IPs
for ip in $STATIC_IPS; do
  echo "ipset add $IPSET_NAME $ip"
  ipset add -exist "$IPSET_NAME" "$ip"
done

# Add resolved IPs
for domain in $DOMAINS; do
  for ip in $(dig +short A "$domain"); do
    echo "ipset add $IPSET_NAME $ip for domain $domain"
    ipset add -exist "$IPSET_NAME" "$ip"
  done
done

sleep 5

ipset save
