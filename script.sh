#!/bin/bash

YOUR_NS1="ns1.centos-webpanel.com"
YOUR_NS2="ns2.centos-webpanel.com"

NAMED_ZONES_DIR="/var/named"
OUTPUT_FILE="dominios_dns_incorreto.txt"

echo "Iniciando a verificação de DNS para domínios com zona DNS em $NAMED_ZONES_DIR..."
echo "Servidores DNS esperados: $YOUR_NS1 e $YOUR_NS2"
echo "Resultados incorretos serão salvos em: $OUTPUT_FILE"
echo "---"

> "$OUTPUT_FILE"

DOMAINS=$(find "$NAMED_ZONES_DIR" -maxdepth 1 -type f -name "*.db" \
          ! -name "localhost.db" \
          ! -name "named.localhost" \
          ! -name "named.empty" \
          ! -name "*.reverse" \
          -printf "%f\n" | sed 's/\.db$//' | sort -u)

TOTAL_DOMAINS=$(echo "$DOMAINS" | wc -l)
PROCESSED_COUNT=0
CORRECT_DNS_COUNT=0

echo "Total de domínios encontrados para verificação: $TOTAL_DOMAINS"
echo "---"

for DOMAIN in $DOMAINS; do
    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
    
    if [[ "$DOMAIN" == "$(hostname -d)" || "$DOMAIN" == "localhost" ]]; then
        echo "  - Pulando hostname/localhost: $DOMAIN"
        continue
    fi

    echo "  - ($PROCESSED_COUNT/$TOTAL_DOMAINS) Checando domínio: $DOMAIN"
    CURRENT_NSS=$(dig +time=5 +tries=3 +short NS "$DOMAIN" | sed 's/\.$//' | sort)

    if ! echo "$CURRENT_NSS" | grep -q "^$YOUR_NS1$" || ! echo "$CURRENT_NSS" | grep -q "^$YOUR_NS2$"; then
        echo "    ❌ ALERTA: $DOMAIN NÃO aponta para seus servidores DNS"
        echo "$DOMAIN" >> "$OUTPUT_FILE"
        echo "      Servidores DNS atuais para $DOMAIN:"
        echo "$CURRENT_NSS" | sed 's/^/        - /'
        echo "      Servidores DNS esperados: $YOUR_NS1, $YOUR_NS2"
    else
        if [ $(echo "$CURRENT_NSS" | wc -l) -ne 2 ]; then
            echo "    ⚠️ ALERTA: $DOMAIN aponta para seus servidores DNS, mas **outros NS também foram encontrados**."
            echo "$DOMAIN" >> "$OUTPUT_FILE"
            echo "      Servidores DNS atuais para $DOMAIN:"
            echo "$CURRENT_NSS" | sed 's/^/        - /'
            echo "      Servidores DNS esperados: $YOUR_NS1, $YOUR_NS2"
        else
            CORRECT_DNS_COUNT=$((CORRECT_DNS_COUNT + 1))
            echo "    ✅ OK: $DOMAIN aponta **exclusivamente** para seus servidores DNS. (Total OKs: $CORRECT_DNS_COUNT)"
        fi
    fi
done

echo "---"
echo "Verificação concluída. $PROCESSED_COUNT domínios processados."
echo "Os domínios com apontamento DNS incorreto foram salvos em: $(pwd)/$OUTPUT_FILE"
echo "Total de domínios com DNS correto: $CORRECT_DNS_COUNT"
