
#!/bin/bash

set -Eeuo pipefail

# =========================================
# G6 - DATA PROCESSING PIPELINE
# =========================================

CONTAINER_NAME="g6-glue-runtime"

# =========================================
# 1. ENTRADA NO CONTAINER
# =========================================

if [ "${G6_PIPELINE_IN_CONTAINER:-0}" != "1" ]; then

    if ! docker inspect \
        --format '{{.State.Running}}' \
        "$CONTAINER_NAME" 2>/dev/null | grep -q true; then

        echo "ERRO: Container Glue não está em execução."

        exit 1

    fi

    exec docker exec \
        -e G6_PIPELINE_IN_CONTAINER=1 \
        "$CONTAINER_NAME" \
        bash /home/hadoop/app/scripts/run_pipeline.sh

fi

# =========================================
# 2. CONFIGURAÇÕES INTERNAS
# =========================================

APP_PATH="/home/hadoop/app"

NOTEBOOK_PATH="${APP_PATH}/notebooks"

OUTPUT_PATH="${APP_PATH}/output/notebooks"

LOG_PATH="/home/hadoop/logs"

LOCK_FILE="/tmp/g6-pipeline.lock"

KERNEL_NAME="glue6"

AWS_REGION="us-east-1"

EXECUTION_ID=$(date +"%Y%m%d_%H%M%S")

EXECUTION_OUTPUT="${OUTPUT_PATH}/${EXECUTION_ID}"

CURRENT_NOTEBOOK="Inicialização"

PIPELINE_STARTED_AT=$(date)

# =========================================
# 3. TRATAMENTO DE ERROS
# =========================================

on_error() {

    EXIT_CODE=$?

    echo
    echo "========================================="
    echo " PIPELINE INTERROMPIDO"
    echo "========================================="

    echo "Notebook: ${CURRENT_NOTEBOOK}"

    echo "Execução: ${EXECUTION_ID}"

    echo "Código de erro: ${EXIT_CODE}"

    echo "Início: ${PIPELINE_STARTED_AT}"

    echo "Falha: $(date)"

    echo "Resultados: ${EXECUTION_OUTPUT}"

    echo "========================================="

    exit "$EXIT_CODE"
}

trap on_error ERR

# =========================================
# 4. PREPARAÇÃO
# =========================================

mkdir -p "$LOG_PATH"

mkdir -p "$OUTPUT_PATH"

mkdir -p "$EXECUTION_OUTPUT"

cd "$APP_PATH"

export PYTHONPATH="${APP_PATH}"

export AWS_REGION

export AWS_DEFAULT_REGION="$AWS_REGION"

# =========================================
# 5. CONTROLE DE CONCORRÊNCIA
# =========================================

exec 200>"$LOCK_FILE"

if ! flock -n 200; then

    echo "ERRO: Já existe uma execução do pipeline."

    exit 1

fi

# =========================================
# 6. VALIDAÇÃO RUNTIME
# =========================================

CURRENT_NOTEBOOK="Validação AWS Glue Runtime"

echo "Validando ambiente..."

python3 - <<'PY'

import sys
import boto3
import pyspark
import awsglue
import papermill
import ipykernel

print("Python:", sys.version)

print("Spark:", pyspark.__version__)

print("Boto3:", boto3.__version__)

print("Papermill:", papermill.__version__)

print("AWS Glue Libraries: OK")

PY

# =========================================
# 7. VALIDAÇÃO AWS
# =========================================

CURRENT_NOTEBOOK="Validação AWS"

python3 - <<'PY'

import boto3

sts = boto3.client(
    "sts",
    region_name="us-east-1"
)

identity = sts.get_caller_identity()

print("AWS Account:", identity["Account"])

print("AWS ARN:", identity["Arn"])

glue = boto3.client(
    "glue",
    region_name="us-east-1"
)

response = glue.get_databases(
    MaxResults=1
)

print("Glue API: OK")

print(
    "Databases:",
    len(response.get("DatabaseList", []))
)

PY

# =========================================
# 8. VALIDAÇÃO KERNEL
# =========================================

CURRENT_NOTEBOOK="Validação Kernel"

jupyter kernelspec list

if ! jupyter kernelspec list | grep -q "$KERNEL_NAME"; then

    echo "ERRO: Kernel ${KERNEL_NAME} não encontrado."

    exit 1

fi

# =========================================
# 9. VALIDAÇÃO STARTUP
# =========================================

CURRENT_NOTEBOOK="Validação Startup"

if [ ! -f "${APP_PATH}/startup/00-spark-config.py" ]; then

    echo "ERRO: Startup Spark não encontrado."

    exit 1

fi

if [ ! -f "${APP_PATH}/config/config.py" ]; then

    echo "ERRO: Configuração Spark não encontrada."

    exit 1

fi

# =========================================
# 10. ORDEM DOS NOTEBOOKS
# =========================================

NOTEBOOKS=(

    "01_ingestao.ipynb"

    "02_validacao.ipynb"

    "03_tratamento.ipynb"

    "04_enriquecimento.ipynb"

    "05_transformacao.ipynb"

    "06_modelagem.ipynb"

    "07_publicacao.ipynb"

)

TOTAL=${#NOTEBOOKS[@]}

# =========================================
# 11. VALIDAÇÃO NOTEBOOKS
# =========================================

CURRENT_NOTEBOOK="Validação dos notebooks"

for NOTEBOOK in "${NOTEBOOKS[@]}"; do

    INPUT="${NOTEBOOK_PATH}/${NOTEBOOK}"

    if [ ! -f "$INPUT" ]; then

        echo "ERRO: Notebook não encontrado: $INPUT"

        exit 1

    fi

done

# =========================================
# 12. INICIALIZAÇÃO
# =========================================

echo
echo "========================================="
echo " G6 - DATA PROCESSING PIPELINE"
echo "========================================="

echo "Runtime: AWS Glue 6.0"

echo "Spark: 4.1.1"

echo "Execução: ${EXECUTION_ID}"

echo "Início: ${PIPELINE_STARTED_AT}"

echo "Total: ${TOTAL}"

echo "Resultados: ${EXECUTION_OUTPUT}"

echo "========================================="

# =========================================
# 13. EXECUÇÃO SEQUENCIAL
# =========================================

CURRENT=0

for NOTEBOOK in "${NOTEBOOKS[@]}"; do

    CURRENT=$((CURRENT + 1))

    CURRENT_NOTEBOOK="$NOTEBOOK"

    INPUT="${NOTEBOOK_PATH}/${NOTEBOOK}"

    OUTPUT="${EXECUTION_OUTPUT}/${NOTEBOOK}"

    echo
    echo "========================================="
    echo " EXECUTANDO ${CURRENT}/${TOTAL}"
    echo " Notebook: ${NOTEBOOK}"
    echo " Início: $(date)"
    echo "========================================="

    papermill \
        "$INPUT" \
        "$OUTPUT" \
        --kernel "$KERNEL_NAME" \
        -p execution_id "$EXECUTION_ID"

    echo "Notebook concluído: ${NOTEBOOK}"

    echo "Resultado: ${OUTPUT}"

done

# =========================================
# 14. FINALIZAÇÃO
# =========================================

PIPELINE_FINISHED_AT=$(date)

echo
echo "========================================="
echo " PIPELINE CONCLUÍDO COM SUCESSO"
echo "========================================="

echo "Execução: ${EXECUTION_ID}"

echo "Notebooks: ${TOTAL}"

echo "Início: ${PIPELINE_STARTED_AT}"

echo "Finalização: ${PIPELINE_FINISHED_AT}"

echo "Resultados: ${EXECUTION_OUTPUT}"

echo "========================================="

exit 0