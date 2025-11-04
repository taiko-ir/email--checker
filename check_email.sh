#!/bin/bash
clear
read -p "Enter domain: " DOMAIN

GREEN='\e[1;92m'
RED='\e[1;91m'
YELLOW='\e[1;93m'
NC='\033[0m'
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
else
    echo -e "${YELLOW}⚠️  IP does NOT match userips ⚠️${NC}"
    echo -e "(Debug: IP='$RAW_IP' vs REAL_IP='$REAL_IP')"
fi

echo ""


# مقایسه رکورد TXT (به‌صورت مجموعه‌ای)
echo "----------------------------------"
echo "2. Checking TXT records for domain..."
echo "----------------------------------"
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

echo "TXT (default):"
echo "$TXT1_JOINED"
echo ""
echo "TXT (netafraz):"
echo "$TXT2_JOINED"
echo ""

# استخراج فقط رکوردهای SPF برای مقایسه
mapfile -t SPF1 < <(printf "%s\n" "${ARR1[@]}" | grep -i '^v=spf1' || true)
mapfile -t SPF2 < <(printf "%s\n" "${ARR2[@]}" | grep -i '^v=spf1' || true)

SPF1_JOINED=$(join_lines "${SPF1[@]}")
SPF2_JOINED=$(join_lines "${SPF2[@]}")

echo "-----------------------------"
echo "SPF Comparison:"
echo "Default SPF: $SPF1_JOINED"
echo "Netafraz SPF: $SPF2_JOINED"
echo "-----------------------------"

# مقایسه فقط SPF
if diff <(echo "$SPF1_JOINED") <(echo "$SPF2_JOINED") &>/dev/null; then
    echo -e "Result: ${GREEN}SPF records match ✅${NC}"
else
    echo -e "Result: ${RED}SPF records do NOT match ❌${NC}"
fi
echo ""

echo "----------------------------------"
echo "3. Checking domainkey TXT records..."
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

# مقایسه با diff
if diff <(echo "$DK1_JOINED") <(echo "$DK2_JOINED") &>/dev/null; then
    echo -e "Result: ${GREEN}domainkey TXT records match ✅${NC}"
else
    echo -e "Result: ${RED}domainkey TXT records do NOT match ❌${NC}"
fi
echo ""

# رکوردهای MX و A
echo "----------------------------------"
echo "4. Checking MX and A records..."
echo "----------------------------------"

MX_RECORDS=$(dig +short MX "$DOMAIN" | grep -v '^;' | awk '{print $2}' | sed 's/\.$//')
A_RECORD=$(dig +short A "mail.${DOMAIN}" | head -n1 | tr -d '[:space:]')

# وضعیت اولیه
MX_OK=false
A_OK=false
IP_MATCH_OK=false

# بررسی MX: آیا mail.${DOMAIN} در MX وجود دارد؟
if echo "$MX_RECORDS" | grep -q "^mail\.${DOMAIN}$" 2>/dev/null; then
    MX_OK=true
fi

# بررسی A رکورد
if [ -n "$A_RECORD" ]; then
    A_OK=true
    # بررسی تطابق IP
    if [ "$A_RECORD" = "$REAL_IP" ]; then
        IP_MATCH_OK=true
    fi
fi

# نمایش نتایج
echo -e "MX Records:"
if [ "$MX_OK" = true ]; then
    echo -e "${GREEN}$(echo "$MX_RECORDS" | sed "s/^mail\.${DOMAIN}$/& (OK)/")${NC}"
else
    echo -e "${RED}Error: mail.${DOMAIN} not found in MX records!${NC}"
    echo -e "${RED}Current MX: ${MX_RECORDS:-None}${NC}"
fi
echo ""

echo -e "A Record for mail.${DOMAIN}:"
if [ "$A_OK" = true ]; then
    if [ "$IP_MATCH_OK" = true ]; then
        echo -e "${GREEN}${A_RECORD} (Matches user IP: ${REAL_IP})${NC}"
    else
        echo -e "${RED}${A_RECORD} (Does NOT match user IP: ${REAL_IP})${NC}"
    fi
else
    echo -e "${RED}Error: No A record found for mail.${DOMAIN}!${NC}"
fi
echo ""

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
echo "$MAILLS_OUTPUT"
echo ""

if echo "$MAILLS_OUTPUT" | grep -q "$DOMAIN"; then
    echo -e "${GREEN}✅ maills output is valid${NC}"
else
    echo -e "${RED}❌ maills output does NOT contain domain${NC}"
fi

