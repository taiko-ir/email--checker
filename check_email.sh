#!/bin/bash

# دریافت دامنه از ورودی
read -p "Enter domain: " DOMAIN

echo "----------------------------------"
echo "1. Checking IP and SMTP host info..."
echo "----------------------------------"
IPCHECK_OUTPUT=$(ipcheck -rs "$DOMAIN")

# استخراج IP Address و SMTP host name
IP_ADDRESS=$(echo "$IPCHECK_OUTPUT" | grep "IP Address:" | awk '{print $3}')
SMTP_HOST=$(echo "$IPCHECK_OUTPUT" | grep "SMTP host name:" | cut -d: -f2 | xargs)

echo "IP Address: $IP_ADDRESS"
echo "SMTP host name: $SMTP_HOST"
echo ""

# مقایسه رکورد TXT
echo "----------------------------------"
echo "2. Checking TXT records for domain..."
echo "----------------------------------"
TXT1=$(dig +short TXT "$DOMAIN" | tr -d '"')
TXT2=$(dig @ns.netafraz.com +short TXT "$DOMAIN" | tr -d '"')

echo "TXT (default): $TXT1"
echo "TXT (netafraz): $TXT2"
if [ "$TXT1" = "$TXT2" ]; then
  echo "Result: TXT records match ✅"
else
  echo "Result: TXT records do NOT match ❌"
fi
echo ""

# مقایسه رکورد domainkey
echo "----------------------------------"
echo "3. Checking domainkey TXT records..."
echo "----------------------------------"
DK1=$(dig +short TXT "x._domainkey.$DOMAIN" | tr -d '"')
DK2=$(dig @ns.netafraz.com +short TXT "x._domainkey.$DOMAIN" | tr -d '"')

echo "x._domainkey TXT (default): $DK1"
echo "x._domainkey TXT (netafraz): $DK2"
if [ "$DK1" = "$DK2" ]; then
  echo "Result: domainkey TXT records match ✅"
else
  echo "Result: domainkey TXT records do NOT match ❌"
fi
echo ""

# رکوردهای MX و A
echo "----------------------------------"
echo "4. Checking MX and A records..."
echo "----------------------------------"
MX_RECORDS=$(dig +short MX "$DOMAIN")
A_RECORD=$(dig +short A "mail.$DOMAIN")

echo "MX records:"
echo "$MX_RECORDS"
echo "A record for mail.$DOMAIN:"
echo "$A_RECORD"
echo ""

# نمایش email_stat
echo "----------------------------------"
echo "5. Email Stat:"
echo "----------------------------------"
email_stat -c
