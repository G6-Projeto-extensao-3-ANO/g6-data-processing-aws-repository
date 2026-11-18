
#!/usr/bin/env bash

set -Eeuo pipefail

COMMAND_ID="${1:?Informe o Command ID}"
INSTANCE_ID="${2:?Informe o Instance ID}"
MAX_ATTEMPTS="${3:-180}"
INTERVAL="${4:-10}"

echo "Aguardando execução do SSM..."
echo "Command ID: $COMMAND_ID"
echo "Instance ID: $INSTANCE_ID"
echo "Limite: $((MAX_ATTEMPTS * INTERVAL / 60)) minutos"

for i in $(seq 1 "$MAX_ATTEMPTS"); do

    RESPONSE=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --output json 2>/dev/null || true)

    STATUS=$(echo "$RESPONSE" | jq -r '.Status // empty')
    DETAILS=$(echo "$RESPONSE" | jq -r '.StatusDetails // empty')

    if [ -z "$STATUS" ]; then
        echo "[$i/$MAX_ATTEMPTS] Aguardando resposta do SSM..."
        sleep "$INTERVAL"
        continue
    fi

    echo "[$i/$MAX_ATTEMPTS] Status: $STATUS | Details: $DETAILS"

    case "$STATUS" in

        Success)
            echo
            echo "========== STDOUT =========="
            echo "$RESPONSE" | jq -r '.StandardOutputContent // ""'

            echo
            echo "Comando executado com sucesso."
            exit 0
            ;;

        Failed|Cancelled|TimedOut)
            echo
            echo "========== STDOUT =========="
            echo "$RESPONSE" | jq -r '.StandardOutputContent // ""'

            echo
            echo "========== STDERR =========="
            echo "$RESPONSE" | jq -r '.StandardErrorContent // ""'

            echo
            echo "Comando SSM falhou: $STATUS"
            exit 1
            ;;

        Pending|InProgress|Delayed|Cancelling)
            sleep "$INTERVAL"
            ;;

        *)
            echo "Status inesperado: $STATUS"
            sleep "$INTERVAL"
            ;;

    esac

done

echo
echo "Tempo limite de espera excedido."

aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --output json || true

exit 1
