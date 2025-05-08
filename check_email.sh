#!/bin/bash

# دریافت دامنه از ورودی
read -p "Enter domain: " DOMAIN

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # بدون رنگ

echo "----------------------------------"
echo "1. Checking IP and  host info..."
echo "----------------------------------"
OUTPUT=$(ipcheck -rs "$DOMAIN")

IP=$(echo "$OUTPUT" | grep 'IP Address' | awk '{print $3}')
HOST=$(echo "$OUTPUT" | grep 'SMTP host name' | cut -d ':' -f2 | xargs)

echo -e "IP Address: ${GREEN}${IP}${NC}"
echo -e "host name: ${GREEN}${HOST}${NC}"

echo "IP Address: $IP_ADDRESS"
echo "SMTP host name: $HOST"
echo ""

# مقایسه رکورد TXT
echo "----------------------------------"
echo "2. Checking TXT records for domain..."
echo "----------------------------------"
TXT1=$(dig +short TXT "$DOMAIN")
TXT2=$(dig @ns.netafraz.com +short TXT "$DOMAIN")

if [ "$TXT1" == "$TXT2" ]; then
    echo -e "Result: ${GREEN}TXT records match ✅${NC}"
else
    echo -e "Result: ${RED}TXT records do NOT match ❌${NC}"
fi
echo ""

# مقایسه رکورد domainkey
echo "----------------------------------"
echo "3. Checking domainkey TXT records..."
echo "----------------------------------"
DKIM1=$(dig +short TXT "x._domainkey.${DOMAIN}")
DKIM2=$(dig @ns.netafraz.com +short TXT "x._domainkey.${DOMAIN}")

if [ "$DKIM1" == "$DKIM2" ]; then
    echo -e "Result: ${GREEN}domainkey TXT records match ✅${NC}"
else
    echo -e "Result: ${RED}domainkey TXT records do NOT match ❌${NC}"
fi
echo ""

# رکوردهای MX و A
echo "----------------------------------"
echo "4. Checking MX and A records..."
echo "----------------------------------"
MX_RECORDS=$(dig +short MX "$DOMAIN")
A_RECORD=$(dig +short A "mail.${DOMAIN}")

echo -e "MX Records:\n${GREEN}${MX_RECORDS}${NC}"
echo ""
echo -e "A Record for mail.${DOMAIN}: ${GREEN}${A_RECORD}${NC}"
echo ""

# نمایش email_stat
echo "----------------------------------"
echo "5. Email Stat:"
echo "----------------------------------"
email_stat -c
