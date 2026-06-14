#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name : dns_mail_check.sh
# Description : Check SPF, DKIM (domainkey) and related DNS records for a domain.
# Author      : Davood Rafiee <davodrafiee@gmail.com>
# Created by  : Davood Rafiee
# -----------------------------------------------------------------------------


clear
#read -rp "Enter domain: " DOMAIN
read -rp "Enter domain: " -e DOMAIN

GREEN='\e[1;92m'
RED='\e[1;91m'
YELLOW='\e[1;93m'
NC='\033[0m'
SUMMARY=()

echo "----------------------------------"
echo "1. Checking IP and host info..."
echo "----------------------------------"

# اجرای ipcheck و حذف escape sequences (رنگ/بولد)
CLEAN_OUTPUT=$(ipcheck -rs "$DOMAIN" | sed 's/\x1B\[[0-9;]*m//g')

# استخراج مقادیر از ipcheck 
#RAW_IP=$(echo "$CLEAN_OUTPUT" | grep 'IP Address' | awk '{print $3}' | tr -d '\r\n[:space:]')
#HOST=$(echo "$CLEAN_OUTPUT" | grep "SMTP host name" | cut -d ':' -f2 | xargs)

# استخراج مقادیر از خروجی تمیز
RAW_IP=$(echo "$CLEAN_OUTPUT" | grep 'IP Address' | awk '{print $3}' | tr -d '\r\n[:space:]')
HOST=$(echo "$CLEAN_OUTPUT" | sed -nE 's/.*SMTP host name[[:space:]]*:[[:space:]]*//p')


# گرفتن IP واقعی از userips و تمیزکاری
REAL_IP=$(userips | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | tr -d '\r\n[:space:]')

# نمایش IP و host
echo -e "IP Address: ${GREEN}${RAW_IP}${NC}"
echo -e "host name: ${GREEN}${HOST}${NC}"

# مقایسه IPها
if [[ "$RAW_IP" == "$REAL_IP" ]]; then
    echo -e "${GREEN}✅ IP matches userips ✔️${NC}"
    SUMMARY+=("IP Match: OK")
else
    echo -e "${YELLOW}⚠️  IP does NOT match userips ⚠️${NC}"
    echo -e "(Debug: IP='$RAW_IP' vs REAL_IP='$REAL_IP')"
    SUMMARY+=("IP Match: FAILED")
fi

echo ""

# مقایسه رکورد TXT (به‌صورت مجموعه‌ای)
echo "----------------------------------"
echo "2. Checking TXT records for domain..."
#echo "----------------------------------"
# دریافت رکوردهای TXT از دو منبع
mapfile -t ARR1 < <(dig +short TXT "$DOMAIN" | tr -d '"' | sort)
mapfile -t ARR2 < <(dig @ns.netafraz.com +short TXT "$DOMAIN" | tr -d '"' | sort)

# تابع کمک برای join با خط جدید
join_lines() {
  printf "%s\n" "${@}"
}

# نمایش تمام رکوردهای TXT
TXT1_JOINED=$(join_lines "${ARR1[@]}")
TXT2_JOINED=$(join_lines "${ARR2[@]}")

# استخراج فقط رکوردهای SPF برای مقایسه
mapfile -t SPF1 < <(printf "%s\n" "${ARR1[@]}" | grep -i '^v=spf1' || true)
mapfile -t SPF2 < <(printf "%s\n" "${ARR2[@]}" | grep -i '^v=spf1' || true)

SPF1_JOINED=$(join_lines "${SPF1[@]}")
SPF2_JOINED=$(join_lines "${SPF2[@]}")

echo "----------------------------------"
echo "SPF Comparison:"
echo "Default SPF: $SPF1_JOINED"
echo "Netafraz SPF: $SPF2_JOINED"
echo "----------------------------------"

if [[ -z "$SPF1_JOINED" && -z "$SPF2_JOINED" ]]; then
    echo -e "Result: ${RED}No SPF record found in either DNS source ❌${NC}"
    SUMMARY+=("SPF: NOT FOUND")
elif [[ -z "$SPF1_JOINED" || -z "$SPF2_JOINED" ]]; then
    echo -e "Result: ${RED}SPF record missing in one of the DNS sources ❌${NC}"
    SUMMARY+=("SPF: MISSING")
elif diff <(printf '%s\n' "$SPF1_JOINED") <(printf '%s\n' "$SPF2_JOINED") &>/dev/null; then
    echo -e "Result: ${GREEN}SPF records match ✅${NC}"
    SUMMARY+=("SPF: OK")
else
    echo -e "Result: ${RED}SPF records do NOT match ❌${NC}"
    SUMMARY+=("SPF: FAILED")
fi

echo ""
sleep 1

echo "----------------------------------"
echo "3. Checking DKIM TXT records..."
echo "----------------------------------"
# می‌گیریم و کوتیشن‌ها را حذف می‌کنیم
mapfile -t DK1_ARR < <(dig +short TXT "x._domainkey.${DOMAIN}" | tr -d '"' | sort)
mapfile -t DK2_ARR < <(dig @ns.netafraz.com +short TXT "x._domainkey.${DOMAIN}" | tr -d '"' | sort)

# تابع کمک برای join با خط جدید
join_lines() {
  printf "%s\n" "${@}"
}

# لیست‌ها را join می‌کنیم
DK1_JOINED=$(join_lines "${DK1_ARR[@]}")
DK2_JOINED=$(join_lines "${DK2_ARR[@]}")

echo "x._domainkey TXT (default):"
echo "$DK1_JOINED"
echo ""
echo "x._domainkey TXT (netafraz):"
echo "$DK2_JOINED"
echo ""

# مقایسه با در نظر گرفتن حالت خالی بودن
if [[ -z "$DK1_JOINED" && -z "$DK2_JOINED" ]]; then
    # هیچ رکوردی در هیچ‌کدوم نیست
    echo -e "Result: ${RED}No x._domainkey TXT record found in either DNS source ❌${NC}"
    SUMMARY+=("DomainKey: NOT FOUND")

elif [[ -z "$DK1_JOINED" || -z "$DK2_JOINED" ]]; then
    # فقط یکی از سورس‌ها رکورد دارد
    echo -e "Result: ${RED}x._domainkey TXT record missing in one of the DNS sources ❌${NC}"
    SUMMARY+=("DKIM: MISSING")

elif diff <(printf '%s\n' "$DK1_JOINED") <(printf '%s\n' "$DK2_JOINED") &>/dev/null; then
    echo -e "Result: ${GREEN}domainkey TXT records match ✅${NC}"
    SUMMARY+=("DKIM: OK")

else
    echo -e "Result: ${RED}domainkey TXT records do NOT match ❌${NC}"
    SUMMARY+=("DKIM: FAILED")
fi

echo ""
sleep 1


# رکوردهای MX و A
echo "----------------------------------"
echo "4. Checking MX and A records..."
echo "----------------------------------"

# دریافت رکوردهای MX دامنه (فقط نام هاست‌ها)
MX_RECORDS=$(dig +short MX "$DOMAIN" | awk '{print $2}' | sed 's/\.$//')

# وضعیت اولیه
MX_OK=false
A_OK=false
IP_MATCH_OK=false
MX_HOST=""
MX_IP=""

# نمایش رکوردهای MX
echo -e "MX Records for ${DOMAIN}:"
if [ -z "$MX_RECORDS" ]; then
    echo -e "${RED}Error: No MX record found for ${DOMAIN}!${NC}"
else
    MX_OK=true
    # نمایش همه MXها
    while IFS= read -r mx; do
        echo "  - $mx"
    done <<< "$MX_RECORDS"
fi
echo ""

# بررسی اولین MX (یا همه، اما برای سادگی اولین را بررسی می‌کنیم)
if [ -n "$MX_RECORDS" ]; then
    # اولین MX را انتخاب می‌کنیم
    MX_HOST=$(echo "$MX_RECORDS" | head -n1)
    
    # دریافت IP (A یا AAAA)
    MX_IP=$(dig +short A "$MX_HOST" | head -n1)
    if [ -z "$MX_IP" ]; then
        MX_IP=$(dig +short AAAA "$MX_HOST" | head -n1)
    fi

    if [ -n "$MX_IP" ]; then
        A_OK=true
        if [ "$MX_IP" = "$REAL_IP" ]; then
            IP_MATCH_OK=true
        fi
    fi
fi

# نمایش نتیجه A رکورد MX
echo -e "A Record for MX host (${MX_HOST:-None}):"
if [ "$A_OK" = true ]; then
    if [ "$IP_MATCH_OK" = true ]; then
        echo -e "${GREEN}${MX_IP} (Matches user IP: ${REAL_IP})${NC}"
    else
        echo -e "${YELLOW}${MX_IP} (Does NOT match user IP: ${REAL_IP})${NC}"
    fi
else
    echo -e "${RED}Error: No A/AAAA record found for MX host '${MX_HOST:-None}'!${NC}"
fi
echo ""
sleep 1

if [ "$MX_OK" = true ]; then
    SUMMARY+=("MX: OK")
else
    SUMMARY+=("MX: FAILED")
fi

if [ "$A_OK" = true ]; then
    SUMMARY+=("MX A Record: OK")
else
    SUMMARY+=("MX A Record: FAILED")
fi

if [ "$IP_MATCH_OK" = true ]; then
    SUMMARY+=("MX IP Match: OK")
else
    SUMMARY+=("MX IP Match: FAILED")
fi

# نمایش email_stat
echo "----------------------------------"
echo "5. Email Stat:"
echo "----------------------------------"
# اجرای email_stat و گرفتن stderr
ERROR_OUTPUT=$(email_stat -c 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    # فقط پیام خطا با رنگ قرمز
    echo -e "${RED}${ERROR_OUTPUT}${NC}"
else
    # خروجی عادی
    echo "$ERROR_OUTPUT"
fi
echo "----------------------------------"
echo "6. Checking maills output..."
echo "----------------------------------"


MAILLS_OUTPUT=$(maills "$DOMAIN")

# Ask user if they want to see the maills output
read -r -t 3 -p "Do you want to display the email's list? [y/N]: " SHOW_MAILLS || { SHOW_MAILLS="N"; echo; }

if [[ "$SHOW_MAILLS" =~ ^[Yy]$ ]]; then
    echo "$MAILLS_OUTPUT"
    echo ""
fi


echo ""
echo "=========================================="
echo "SUMMARY"
echo "=========================================="

for item in "${SUMMARY[@]}"; do
    if [[ "$item" == *"OK"* ]]; then
        echo -e "${GREEN}✅ $item${NC}"
    else
        echo -e "${RED}❌ $item${NC}"
    fi
done

echo "=========================================="
