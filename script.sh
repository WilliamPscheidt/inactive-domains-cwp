#!/bin/bash

YOUR_NS1="ns1.superdominiosparking.org"
YOUR_NS2="ns2.superdominiosparking.org"

NAMED_ZONES_DIR="/var/named"
OUTPUT_FILE="dns_invalidos.txt"

> "$OUTPUT_FILE"

DOMAINS=$(find "$NAMED_ZONES_DIR" -maxdepth 1 -type f -name "*.db" \
          ! -name "localhost.db" \
          ! -name "named.localhost" \
          ! -name "named.empty" \
          ! -name "*.reverse" \
          -printf "%f\n" | sed 's/\.db$//' | sort -u)

TOTAL_DOMAINS=$(echo "$DOMAINS" | wc -l)
PROCESSED_COUNT=0

echo "Total de domínios encontrados: $TOTAL_DOMAINS"
echo "---"

for DOMAIN in $DOMAINS; do
    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
    
    if [[ "$DOMAIN" == "$(hostname -d)" || "$DOMAIN" == "localhost" ]]; then
        echo "  - Pulando hostname/localhost: $DOMAIN"
        continue
    fi

    echo "  - ($PROCESSED_COUNT/$TOTAL_DOMAINS) Checando domínio: $DOMAIN"

    CURRENT_NSS=$(dig +time=5 +tries=1 +short NS "$DOMAIN" | sort)

    if ! echo "$CURRENT_NSS" | grep -q "^$YOUR_NS1$" || ! echo "$CURRENT_NSS" | grep -q "^$YOUR_NS2$"; then
        echo "    ❌ $DOMAIN NÃO aponta para o superdominiosparking"
        echo "$DOMAIN" >> "$OUTPUT_FILE"
        echo "      Servidores DNS atuais para $DOMAIN:"
        if [ -z "$CURRENT_NSS" ]; then
            echo "        Nenhum servidor DNS encontrado."
        else
            echo "$CURRENT_NSS" | sed 's/^/        - /'
        fi
        echo "      Servidores DNS esperados: $YOUR_NS1, $YOUR_NS2"
    else
        if [ $(echo "$CURRENT_NSS" | wc -l) -ne 2 ]; then
            echo "    ⚠️ $DOMAIN aponta para seus servidores DNS, mas **outros NS também foram encontrados**."
            echo "$DOMAIN" >> "$OUTPUT_FILE"
            echo "      Servidores DNS atuais para $DOMAIN:"
            echo "$CURRENT_NSS" | sed 's/^/        - /'
            echo "      Servidores DNS esperados: $YOUR_NS1, $YOUR_NS2"
        else
            echo "    ✅ $DOMAIN aponta **exclusivamente** para seus servidores DNS."
        fi
    fi
done

echo "---"
echo "Verificação concluída. $PROCESSED_COUNT domínios processados."
echo "Os domínios com apontamento DNS incorreto foram salvos em: $(pwd)/$OUTPUT_FILE"
