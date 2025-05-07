#!/bin/bash

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # بدون رنگ

read -p "Enter domain: " DOMAIN

echo -e "\nChecking IP info..."
OUTPUT=$(ipcheck -rs "$DOMAIN")

IP=$(echo "$OUTPUT" | grep 'IP Address' | awk '{print $3}')
SMTP_HOST=$(echo "$OUTPUT" | grep 'SMTP host name' | cut -d ':' -f2 | xargs)

echo -e "IP Address: ${GREEN}${IP}${NC}"
echo -e "SMTP host name: ${GREEN}${SMTP_HOST}${NC}"

echo -e "\nChecking TXT records..."
TXT1=$(dig +short TXT "$DOMAIN")
TXT2=$(dig @ns.netafraz.com +short TXT "$DOMAIN")

if [ "$TXT1" == "$TXT2" ]; then
    echo -e "Result: ${GREEN}TXT records match ✅${NC}"
else
    echo -e "Result: ${RED}TXT records do NOT match ❌${NC}"
fi

echo -e "\nChecking domainkey TXT records..."
DKIM1=$(dig +short TXT "x._domainkey.${DOMAIN}")
DKIM2=$(dig @ns.netafraz.com +short TXT "x._domainkey.${DOMAIN}")

if [ "$DKIM1" == "$DKIM2" ]; then
    echo -e "Result: ${GREEN}domainkey TXT records match ✅${NC}"
else
    echo -e "Result: ${RED}domainkey TXT records do NOT match ❌${NC}"
fi

echo -e "\nChecking MX and mail A records..."
MX_RECORDS=$(dig +short MX "$DOMAIN")
A_RECORD=$(dig +short A "mail.${DOMAIN}")

echo -e "MX Records:\n${GREEN}${MX_RECORDS}${NC}"
echo -e "A Record for mail.${DOMAIN}: ${GREEN}${A_RECORD}${NC}"

echo -e "\nChecking email_stat..."
email_stat -c
