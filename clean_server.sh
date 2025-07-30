#!/bin/bash

INPUT_FILE="dns_incorretos2.txt" 
NAMED_ZONES_DIR="/var/named"
NAMED_CONF_DOMAINS="/etc/named.conf" 
APACHE_VHOSTS_DIR="/usr/local/apache/conf.d/vhosts"
ACCOUNTS_TO_CHECK_FILE="contas_diretorio.txt"

echo "======================================================================"
echo "      INICIANDO LIMPEZA DE DNS/VHOSTS E IDENTIFICAÇÃO DE CONTAS      "
echo "======================================================================"
echo "Lendo domínios a serem processados de: $INPUT_FILE"
echo "Contas para verificação manual em /home/ serão salvas em: $ACCOUNTS_TO_CHECK_FILE"
echo "----------------------------------------------------------------------"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/manual_delete_backup_${TIMESTAMP}"
echo "Criando backup de configurações antes de prosseguir em: $BACKUP_DIR"
sudo mkdir -p "$BACKUP_DIR"
sudo cp -a "$NAMED_ZONES_DIR" "$BACKUP_DIR/named_zones"
sudo cp -a "$NAMED_CONF_DOMAINS" "$BACKUP_DIR/named.conf_backup" 
sudo cp -a "$APACHE_VHOSTS_DIR" "$BACKUP_DIR/apache_vhosts"
echo "Backup concluído em: $BACKUP_DIR"
echo "----------------------------------------------------------------------"

# Verifica se o arquivo de entrada existe
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERRO: O arquivo '$INPUT_FILE' não foi encontrado."
    echo "Certifique-se de que o script de verificação de DNS foi executado e gerou a lista."
    exit 1
fi

> "$ACCOUNTS_TO_CHECK_FILE"

SUCCESS_COUNT=0
FAIL_COUNT=0

while IFS= read -r DOMAIN_TO_DELETE; do
    DOMAIN_TO_DELETE=$(echo "$DOMAIN_TO_DELETE" | xargs)
    if [ -z "$DOMAIN_TO_DELETE" ]; then
        continue
    fi

    echo "Processando domínio: $DOMAIN_TO_DELETE"
    
    VHOST_FILE=$(grep -lRE "ServerName\s+$DOMAIN_TO_DELETE|ServerAlias\s+.*$DOMAIN_TO_DELETE" "$APACHE_VHOSTS_DIR" 2>/dev/null | head -n 1)

    USER_FOUND=""
    if [ -n "$VHOST_FILE" ]; then
        USER_FOUND=$(grep -m 1 -Eo "(SuexecUserGroup|suPHP_UserGroup|AssignUserID|RUidGid)[[:space:]]+[a-zA-Z0-9_-]+" "$VHOST_FILE" | awk '{print $2}' | head -n 1)
    fi

    if [ -z "$USER_FOUND" ]; then
        echo "  ⚠️ ALERTA: Não foi possível identificar o usuário CWP pelo VHost para o domínio '$DOMAIN_TO_DELETE'."
        echo "  Pule a exclusão automática da zona DNS e VHost para este domínio."
        echo "----------------------------------------------------------------------"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo "  Usuário CWP identificado: $USER_FOUND"

    if [ "$USER_FOUND" != "park" ]; then
        if ! grep -q "^$USER_FOUND$" "$ACCOUNTS_TO_CHECK_FILE"; then
            echo "$USER_FOUND" >> "$ACCOUNTS_TO_CHECK_FILE"
            echo "  Usuário '$USER_FOUND' adicionado à lista para verificação manual de /home/."
        fi
    fi

    if grep -q "zone \"$DOMAIN_TO_DELETE\"" "$NAMED_CONF_DOMAINS"; then
        echo "  Removendo entrada da zona '$DOMAIN_TO_DELETE' de $NAMED_CONF_DOMAINS..."
        sudo sed -i "/\/\/ zone $DOMAIN_TO_DELETE/,/\/\/ zone_end $DOMAIN_TO_DELETE/{d}" "$NAMED_CONF_DOMAINS"
        sudo sed -i "/zone \"$DOMAIN_TO_DELETE\" {type master; file \"\/var\/named\/$DOMAIN_TO_DELETE.db\";};/d" "$NAMED_CONF_DOMAINS"
        
        if [ $? -eq 0 ]; then
            echo "  Entrada removida com sucesso de $NAMED_CONF_DOMAINS."
        else
            echo "  ❌ ERRO: Falha ao remover entrada de zona de $NAMED_CONF_DOMAINS. Verifique manualmente."
            echo "$DOMAIN_TO_DELETE (ERRO: named.conf)" >> "$BACKUP_DIR/failed_deletions.log"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            continue 
        fi
    else
        echo "  Entrada de zona '$DOMAIN_TO_DELETE' não encontrada em $NAMED_CONF_DOMAINS (já removida ou não existia)."
    fi

    ZONE_FILE="$NAMED_ZONES_DIR/$DOMAIN_TO_DELETE.db"
    if [ -f "$ZONE_FILE" ]; then
        echo "  Removendo arquivo de zona $ZONE_FILE..."
        sudo rm -f "$ZONE_FILE"
        if [ $? -eq 0 ]; then
            echo "  Arquivo de zona removido com sucesso."
        else
            echo "  ❌ ERRO: Falha ao remover arquivo de zona $ZONE_FILE. Verifique manualmente."
            echo "$DOMAIN_TO_DELETE (ERRO: .db file)" >> "$BACKUP_DIR/failed_deletions.log"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            continue
        fi
    else
        echo "  Arquivo de zona $ZONE_FILE não encontrado (já removido ou não existia)."
    fi

    if [ -n "$VHOST_FILE" ]; then
        echo "  Encontrado VHost: $VHOST_FILE"

        if grep -q "ServerName\s+$DOMAIN_TO_DELETE" "$VHOST_FILE" && ! grep -q "ServerAlias\s+.*$DOMAIN_TO_DELETE" "$VHOST_FILE"; then
            echo "  Removendo arquivo VHost principal para '$DOMAIN_TO_DELETE'..."
            sudo rm -f "$VHOST_FILE"
            if [ $? -eq 0 ]; then
                echo "  VHost principal removido com sucesso."
            else
                echo "  ❌ ERRO: Falha ao remover VHost principal '$VHOST_FILE'. Verifique manualmente."
                echo "$DOMAIN_TO_DELETE (ERRO: VHost file primary)" >> "$BACKUP_DIR/failed_deletions.log"
                FAIL_COUNT=$((FAIL_COUNT + 1))
                continue
            fi
        else
            echo "  Removendo ServerAlias/ServerName específico de '$DOMAIN_TO_DELETE' em '$VHOST_FILE'..."
            sudo sed -i "/^[[:space:]]*ServerAlias[[:space:]]\+.*$DOMAIN_TO_DELETE.*$/d" "$VHOST_FILE"
            sudo sed -i "/^[[:space:]]*ServerName[[:space:]]\+$DOMAIN_TO_DELETE.*$/d" "$VHOST_FILE"
            sudo sed -i '/^[[:space:]]*$/d' "$VHOST_FILE"
            if [ $? -eq 0 ]; then
                echo "  ServerAlias/ServerName removido do VHost com sucesso."
            else
                echo "  ❌ ERRO: Falha ao remover ServerAlias/ServerName de '$VHOST_FILE'. Verifique manualmente."
                echo "$DOMAIN_TO_DELETE (ERRO: VHost alias)" >> "$BACKUP_DIR/failed_deletions.log"
                FAIL_COUNT=$((FAIL_COUNT + 1))
                continue
            fi
        fi
    else
        echo "  VHost para '$DOMAIN_TO_DELETE' não encontrado (já removido ou não existia)."
    fi

    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    echo "  ✅ Sucesso: Todas as entradas para '$DOMAIN_TO_DELETE' foram processadas."
    echo "----------------------------------------------------------------------"

done < "$INPUT_FILE"

echo "======================================================================"
echo "          PROCESSO DE EXCLUSÃO DE ZONAS DNS E VHOSTS CONCLUÍDO          "
echo "======================================================================"
echo "Total de domínios processados com sucesso: $SUCCESS_COUNT"
echo "Total de domínios com falhas: $FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "Verifique o log de falhas em: $BACKUP_DIR/failed_deletions.log"
fi
echo "----------------------------------------------------------------------"
echo "Contas identificadas para verificação manual em /home/ foram salvas em:"
echo "$(pwd)/$ACCOUNTS_TO_CHECK_FILE"
echo "----------------------------------------------------------------------"
echo "Agora, REINICIANDO os serviços BIND e Apache para aplicar as mudanças..."

sudo systemctl restart named
if [ $? -eq 0 ]; then
    echo "Serviço BIND (named) reiniciado com sucesso."
else
    echo "❌ ERRO: Falha ao reiniciar o serviço BIND. Verifique manualmente!"
fi

sudo systemctl restart httpd
if [ $? -eq 0 ]; then
    echo "Serviço Apache (httpd) reiniciado com sucesso."
else
    echo "❌ ERRO: Falha ao reiniciar o serviço Apache. Verifique manualmente!"
fi

echo "======================================================================"
echo "          OPERAÇÃO FINALIZADA. VERIFIQUE OS LOGS DO SERVIDOR.          "
echo "======================================================================"
