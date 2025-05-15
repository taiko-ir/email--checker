#!/bin/bash

# دریافت دامنه از ورودی
read -p "Enter domain: " DOMAIN

# رنگ‌ها
GREEN='\e[1;32m'
#'\033[0;32m'
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

echo ""

# مقایسه رکورد TXT (به‌صورت مجموعه‌ای)
echo "----------------------------------"
echo "2. Checking TXT records for domain..."
echo "----------------------------------"
# می‌گیریم و کوتیشن‌ها را حذف می‌کنیم
mapfile -t ARR1 < <(dig +short TXT "$DOMAIN" | tr -d '"' | sort)
mapfile -t ARR2 < <(dig @ns.netafraz.com +short TXT "$DOMAIN" | tr -d '"' | sort)

# تابع کمک برای join با خط جدید
join_lines() {
  printf "%s\n" "${@}"
}

# لیست‌ها را join می‌کنیم
TXT1_JOINED=$(join_lines "${ARR1[@]}")
TXT2_JOINED=$(join_lines "${ARR2[@]}")

echo "TXT (default):"
echo "$TXT1_JOINED"
echo ""
echo "TXT (netafraz):"
echo "$TXT2_JOINED"
echo ""

# مقایسه با diff
if diff <(echo "$TXT1_JOINED") <(echo "$TXT2_JOINED") &>/dev/null; then
    echo -e "Result: ${GREEN}TXT records match ✅${NC}"
else
    echo -e "Result: ${RED}TXT records do NOT match ❌${NC}"
fi
echo ""

# مقایسه رکورد domainkey به‌صورت مجموعه‌ای
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
