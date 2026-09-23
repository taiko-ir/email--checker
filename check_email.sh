#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name : dns_mail_check.sh
# Description : Check SPF, DKIM, DMARC, MX, SSL, and related DNS/mail records.
# Author      : Davood Rafiee <davodrafiee@gmail.com>
# Created by  : Davood Rafiee
# -----------------------------------------------------------------------------


clear
read -rp "Enter domain: " -e DOMAIN

GREEN='\e[1;92m'
RED='\e[1;91m'
YELLOW='\e[1;93m'
NC='\033[0m'
SUMMARY=()

# -----------------------------------------------------------------------------
# Domain normalization and validation
# -----------------------------------------------------------------------------

# Remove all whitespace
DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]')

# Convert to lowercase
DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]')

# Remove protocol
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN#https://}"

# Remove www.
DOMAIN="${DOMAIN#www.}"

# Remove path, query string, and fragment
DOMAIN="${DOMAIN%%/*}"
DOMAIN="${DOMAIN%%\?*}"
DOMAIN="${DOMAIN%%\#*}"

# Remove trailing dot
DOMAIN="${DOMAIN%.}"

# Remove port if entered accidentally, e.g. example.com:443
DOMAIN="${DOMAIN%%:*}"

# Validate domain
if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}Error: Domain cannot be empty.${NC}"
    exit 1
fi

if [[ ! "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]; then
    echo -e "${RED}Error: Invalid domain: '$DOMAIN'${NC}"
    echo "Please enter the domain in this format: example.com"
    exit 1
fi

echo -e "Domain: ${GREEN}${DOMAIN}${NC}"
echo ""

echo "----------------------------------"
echo "1. Checking IP and host info..."
echo "----------------------------------"

# Run ipcheck and remove ANSI escape sequences
CLEAN_OUTPUT=$(ipcheck -rs "$DOMAIN" | sed 's/\x1B\[[0-9;]*m//g')

# Extract values from cleaned output
RAW_IP=$(echo "$CLEAN_OUTPUT" | grep 'IP Address' | awk '{print $3}' | tr -d '\r\n[:space:]')
HOST=$(echo "$CLEAN_OUTPUT" | sed -nE 's/.*SMTP host name[[:space:]]*:[[:space:]]*//p')

# Get the actual IP from userips and clean the output
REAL_IP=$(userips | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | tr -d '\r\n[:space:]')

# Display IP and host
echo -e "IP Address: ${GREEN}${RAW_IP}${NC}"
echo -e "host name: ${GREEN}${HOST}${NC}"

# Compare IP addresses
if [[ "$RAW_IP" == "$REAL_IP" ]]; then
    echo -e "${GREEN}✅ IP matches userips ✔️${NC}"
    SUMMARY+=("IP Match: OK")
else
    echo -e "${YELLOW}⚠️  IP does NOT match userips ⚠️${NC}"
    echo -e "(Debug: IP='$RAW_IP' vs REAL_IP='$REAL_IP')"
    SUMMARY+=("IP Match: FAILED")
fi

echo ""

# Compare TXT records as sets
echo "----------------------------------"
echo "2. Checking TXT records for domain..."

# Get TXT records from both DNS sources
mapfile -t ARR1 < <(dig +short TXT "$DOMAIN" | tr -d '"' | sort)
mapfile -t ARR2 < <(dig @ns.netafraz.com +short TXT "$DOMAIN" | tr -d '"' | sort)

# Helper function to join array entries with new lines
join_lines() {
  printf "%s\n" "${@}"
}

# Join all TXT records for display
TXT1_JOINED=$(join_lines "${ARR1[@]}")
TXT2_JOINED=$(join_lines "${ARR2[@]}")

# Extract only SPF records for comparison
# Other TXT records are not included in SPF validation
mapfile -t SPF1 < <(printf "%s\n" "${ARR1[@]}" | grep -i '^v=spf1' || true)
mapfile -t SPF2 < <(printf "%s\n" "${ARR2[@]}" | grep -i '^v=spf1' || true)

SPF1_JOINED=$(join_lines "${SPF1[@]}")
SPF2_JOINED=$(join_lines "${SPF2[@]}")

SPF1_COUNT=${#SPF1[@]}
SPF2_COUNT=${#SPF2[@]}

echo "----------------------------------"
echo "SPF Comparison:"
echo "Default SPF: $SPF1_JOINED"
echo "Netafraz SPF: $SPF2_JOINED"
echo "----------------------------------"

if [[ "$SPF1_COUNT" -eq 0 && "$SPF2_COUNT" -eq 0 ]]; then
    echo -e "Result: ${RED}No SPF record found in either DNS source ❌${NC}"
    SUMMARY+=("SPF: NOT FOUND")

elif [[ "$SPF1_COUNT" -gt 1 || "$SPF2_COUNT" -gt 1 ]]; then
    echo -e "Result: ${RED}Multiple SPF records detected ❌${NC}"
    echo -e "Default DNS SPF count: ${YELLOW}${SPF1_COUNT}${NC}"
    echo -e "Netafraz DNS SPF count: ${YELLOW}${SPF2_COUNT}${NC}"
    SUMMARY+=("SPF: MULTIPLE RECORDS")

elif [[ "$SPF1_COUNT" -eq 0 || "$SPF2_COUNT" -eq 0 ]]; then
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

# Get DKIM TXT records and remove quotation marks
mapfile -t DK1_ARR < <(dig +short TXT "x._domainkey.${DOMAIN}" | tr -d '"' | sort)
mapfile -t DK2_ARR < <(dig @ns.netafraz.com +short TXT "x._domainkey.${DOMAIN}" | tr -d '"' | sort)

# Helper function to join array entries with new lines
join_lines() {
  printf "%s\n" "${@}"
}

# Join arrays for display
DK1_JOINED=$(join_lines "${DK1_ARR[@]}")
DK2_JOINED=$(join_lines "${DK2_ARR[@]}")

# Normalized versions for comparison
# Remove all whitespace before comparing
DK1_COMPARE=$(printf "%s" "${DK1_ARR[@]}" | tr -d '[:space:]')
DK2_COMPARE=$(printf "%s" "${DK2_ARR[@]}" | tr -d '[:space:]')

echo "x._domainkey TXT (default):"
echo "$DK1_JOINED"
echo ""
echo "x._domainkey TXT (netafraz):"
echo "$DK2_JOINED"
echo ""

# Compare records while handling empty results
if [[ -z "$DK1_JOINED" && -z "$DK2_JOINED" ]]; then
    # No DKIM record exists in either DNS source
    echo -e "Result: ${RED}No x._domainkey TXT record found in either DNS source ❌${NC}"
    SUMMARY+=("DomainKey: NOT FOUND")

elif [[ -z "$DK1_JOINED" || -z "$DK2_JOINED" ]]; then
    # Only one DNS source contains the DKIM record
    echo -e "Result: ${RED}x._domainkey TXT record missing in one of the DNS sources ❌${NC}"
    SUMMARY+=("DKIM: MISSING")

elif [[ "$DK1_COMPARE" == "$DK2_COMPARE" ]]; then
    echo -e "Result: ${GREEN}domainkey TXT records match ✅${NC}"
    SUMMARY+=("DKIM: OK")

else
    echo -e "Result: ${RED}domainkey TXT records do NOT match ❌${NC}"
    SUMMARY+=("DKIM: FAILED")
fi

echo ""
sleep 1


# Check MX and A/AAAA records
echo "----------------------------------"
echo "4. Checking MX and A records..."
echo "----------------------------------"

# Get MX records including priority
MX_FULL_RECORDS=$(dig +short MX "$DOMAIN" | sort -n)

# Extract only MX hostnames
MX_RECORDS=$(printf "%s\n" "$MX_FULL_RECORDS" | awk '{print $2}' | sed 's/\.$//')

# Initial status values
MX_OK=false
A_OK=false
IP_MATCH_OK=false
MX_HOST=""
MX_IP=""

# Display MX records
echo -e "MX Records for ${DOMAIN}:"

if [ -z "$MX_RECORDS" ]; then
    echo -e "${RED}Error: No MX record found for ${DOMAIN}!${NC}"
else
    MX_OK=true

    while IFS= read -r mx_record; do
        [ -z "$mx_record" ] && continue

        MX_PRIORITY=$(echo "$mx_record" | awk '{print $1}')
        MX_HOST=$(echo "$mx_record" | awk '{print $2}' | sed 's/\.$//')

        echo ""
        echo "MX Priority: $MX_PRIORITY"
        echo "MX Host: $MX_HOST"

        # Get all A records
        mapfile -t MX_A_IPS < <(dig +short A "$MX_HOST")

        # Get all AAAA records
        mapfile -t MX_AAAA_IPS < <(dig +short AAAA "$MX_HOST")

        if [[ ${#MX_A_IPS[@]} -gt 0 || ${#MX_AAAA_IPS[@]} -gt 0 ]]; then
            A_OK=true

            if [[ ${#MX_A_IPS[@]} -gt 0 ]]; then
                echo "A Record(s):"

                for MX_IP in "${MX_A_IPS[@]}"; do
                    echo "  - $MX_IP"

                    if [ "$MX_IP" = "$REAL_IP" ]; then
                        IP_MATCH_OK=true
                    fi
                done
            fi

            if [[ ${#MX_AAAA_IPS[@]} -gt 0 ]]; then
                echo "AAAA Record(s):"

                for MX_IP in "${MX_AAAA_IPS[@]}"; do
                    echo "  - $MX_IP"
                done
            fi

        else
            echo -e "${RED}Error: No A/AAAA record found for MX host '$MX_HOST'!${NC}"
        fi

    done <<< "$MX_FULL_RECORDS"
fi

echo ""

if [ "$A_OK" = true ]; then
    if [ "$IP_MATCH_OK" = true ]; then
        echo -e "${GREEN}At least one MX IP matches user IP: ${REAL_IP}${NC}"
    else
        echo -e "${YELLOW}No MX IP matches user IP: ${REAL_IP}${NC}"
    fi
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


echo "----------------------------------"
echo "5. Checking DMARC record..."
echo "----------------------------------"

DMARC_RECORD=$(dig +short TXT "_dmarc.${DOMAIN}" | tr -d '"' | grep -i '^v=DMARC1' || true)

echo "_dmarc.${DOMAIN} TXT:"

if [[ -z "$DMARC_RECORD" ]]; then
    echo -e "${RED}No DMARC record found ❌${NC}"
    SUMMARY+=("DMARC: NOT FOUND")
else
    echo "$DMARC_RECORD"

    DMARC_POLICY=$(echo "$DMARC_RECORD" | grep -oEi '(^|;[[:space:]]*)p[[:space:]]*=[[:space:]]*(none|quarantine|reject)' | head -n1 | sed -E 's/.*=[[:space:]]*//I')

    if [[ -n "$DMARC_POLICY" ]]; then
        echo -e "Result: ${GREEN}DMARC record found ✅ (p=${DMARC_POLICY})${NC}"
        SUMMARY+=("DMARC: OK (p=${DMARC_POLICY})")
    else
        echo -e "Result: ${YELLOW}DMARC record found but policy not detected ⚠️${NC}"
        SUMMARY+=("DMARC: FOUND")
    fi
fi

echo ""
sleep 1


echo "----------------------------------"
echo "6. Checking SSL certificates..."
echo "----------------------------------"

check_ssl() {
    local SSL_HOST="$1"

    echo "Checking SSL for $SSL_HOST..."

    SSL_CERT=$(
        timeout 8 openssl s_client \
            -connect "${SSL_HOST}:443" \
            -servername "$SSL_HOST" \
            </dev/null 2>/dev/null |
        openssl x509 -noout -subject -issuer -dates 2>/dev/null
    )

    if [[ -n "$SSL_CERT" ]]; then
        if timeout 8 openssl s_client \
            -connect "${SSL_HOST}:443" \
            -servername "$SSL_HOST" \
            </dev/null 2>/dev/null |
            openssl x509 -noout -checkend 0 >/dev/null 2>&1
        then
            echo -e "${GREEN}SSL certificate found and valid ✅${NC}"
            return 0
        else
            echo -e "${RED}SSL certificate found but expired/invalid ❌${NC}"
            return 2
        fi
    else
        echo -e "${RED}No SSL certificate found ❌${NC}"
        return 1
    fi
}

check_ssl "$DOMAIN"
DOMAIN_SSL_STATUS=$?

if [[ "$DOMAIN_SSL_STATUS" -eq 0 ]]; then
    SUMMARY+=("SSL $DOMAIN: OK")
elif [[ "$DOMAIN_SSL_STATUS" -eq 2 ]]; then
    SUMMARY+=("SSL $DOMAIN: EXPIRED")
else
    SUMMARY+=("SSL $DOMAIN: NOT FOUND")
fi

echo ""

MAIL_DOMAIN="mail.${DOMAIN}"

check_ssl "$MAIL_DOMAIN"
MAIL_SSL_STATUS=$?

if [[ "$MAIL_SSL_STATUS" -eq 0 ]]; then
    SUMMARY+=("SSL $MAIL_DOMAIN: OK")
elif [[ "$MAIL_SSL_STATUS" -eq 2 ]]; then
    SUMMARY+=("SSL $MAIL_DOMAIN: EXPIRED")
else
    SUMMARY+=("SSL $MAIL_DOMAIN: NOT FOUND")
fi

echo ""
sleep 1


# Display email_stat output
echo "----------------------------------"
echo "7. Email Stat:"
echo "----------------------------------"

# Run email_stat and capture stderr
ERROR_OUTPUT=$(email_stat -c 2>&1)
EXIT_CODE=$?
CLEAN_EMAIL_OUTPUT=$(echo "$ERROR_OUTPUT" | sed 's/\x1B\[[0-9;]*m//g')

if [ $EXIT_CODE -ne 0 ]; then
    # Display only the error message in red
    echo -e "${RED}${ERROR_OUTPUT}${NC}"
    SUMMARY+=("mail Status: FAILED")

else
    # Display normal output
    echo "$ERROR_OUTPUT"

    if echo "$CLEAN_EMAIL_OUTPUT" | grep 'mail()' | grep -q 'Enabled'; then
        SUMMARY+=("mail Status: OK")
    else
        SUMMARY+=("mail Status: BLOCKED")
    fi
fi


echo "----------------------------------"
echo "8. Checking maills output..."
echo "----------------------------------"


MAILLS_OUTPUT=$(hst-cli email list "$DOMAIN")

# Ask the user whether to display the email account list
read -r -t 3 -p "Do you want to display the email's list? [y/N]: " SHOW_MAILLS || { SHOW_MAILLS="N"; echo; }

if [[ "$SHOW_MAILLS" =~ ^[Yy]$ ]]; then
    echo "$MAILLS_OUTPUT"
    echo ""
fi


echo ""
echo "=========================================="
echo "SUMMARY FOR $DOMAIN"
echo "=========================================="

for item in "${SUMMARY[@]}"; do
    if [[ "$item" == *"OK"* ]]; then
        echo -e "${GREEN}✅ $item${NC}"
    else
        echo -e "${RED}❌ $item${NC}"
    fi
done

echo "=========================================="
