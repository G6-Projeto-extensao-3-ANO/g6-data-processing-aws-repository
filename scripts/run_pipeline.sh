
#!/bin/bash

set -Eeuo pipefail

# =========================================
# G6 - DATA PROCESSING PIPELINE
# =========================================

# =========================================
# 1. CONFIGURAÇÕES
# =========================================

CURRENT_USER="ubuntu"

APP_PATH="/home/ubuntu/app"
VENV_PATH="/home/ubuntu/amb"

NOTEBOOK_PATH="${APP_PATH}/notebooks"
OUTPUT_PATH="${APP_PATH}/output/notebooks"

LOG_PATH="/home/ubuntu/logs"
LOCK_FILE="/tmp/g6-pipeline.lock"

KERNEL_NAME="amb"

AWS_REGION="us-east-1"

GLUE_JARS_DIR="/opt/aws-glue-catalog/jars"
GLUE_CATALOG_JARS=""

EXECUTION_ID=$(date +"%Y%m%d_%H%M%S")
EXECUTION_OUTPUT="${OUTPUT_PATH}/${EXECUTION_ID}"

JAVA_HOME=""

CURRENT_NOTEBOOK="Inicialização"
PIPELINE_STARTED_AT=$(date)

# =========================================
# 2. TRATAMENTO DE ERROS
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

    echo "Resultados parciais: ${EXECUTION_OUTPUT}"

    echo "========================================="

    exit "$EXIT_CODE"
}

trap on_error ERR

# =========================================
# 3. VALIDAÇÃO DO USUÁRIO
# =========================================

if [ "$(id -un)" != "$CURRENT_USER" ]; then

    echo "ERRO: Execute o pipeline como usuário ${CURRENT_USER}."

    exit 1

fi

# =========================================
# 4. PREPARAÇÃO DO AMBIENTE
# =========================================

echo "Preparando ambiente..."

mkdir -p "$LOG_PATH"
mkdir -p "$OUTPUT_PATH"

cd "$APP_PATH"

export PYTHONPATH="${APP_PATH}"
export PATH="${VENV_PATH}/bin:${PATH}"

# =========================================
# 5. CONTROLE DE CONCORRÊNCIA
# =========================================

exec 200>"$LOCK_FILE"

if ! flock -n 200; then

    echo "ERRO: Já existe uma execução do pipeline."

    exit 1

fi

# =========================================
# 6. CONFIGURAÇÃO JAVA
# =========================================

CURRENT_NOTEBOOK="Validação Java"

echo "Validando Java..."

if ! command -v java >/dev/null 2>&1; then

    echo "ERRO: Java não encontrado."

    exit 1

fi

JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")

export JAVA_HOME

java -version

echo "JAVA_HOME: ${JAVA_HOME}"

# =========================================
# 7. CONFIGURAÇÃO AWS
# =========================================

CURRENT_NOTEBOOK="Validação AWS"

echo
echo "Configurando ambiente AWS..."

export AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "AWS Region: ${AWS_REGION}"

# =========================================
# 8. VALIDAÇÃO GLUE JARS
# =========================================

CURRENT_NOTEBOOK="Validação AWS Glue Client"

echo
echo "Validando JARs do Glue..."

if [ ! -d "$GLUE_JARS_DIR" ]; then

    echo "ERRO: Diretório dos JARs não encontrado."

    echo "$GLUE_JARS_DIR"

    exit 1

fi

GLUE_CATALOG_JARS=$(
    find "$GLUE_JARS_DIR" \
        -maxdepth 1 \
        -type f \
        -name "*.jar" \
        | sort \
        | paste -sd, -
)

if [ -z "$GLUE_CATALOG_JARS" ]; then

    echo "ERRO: Nenhum JAR do Glue encontrado."

    exit 1

fi

export GLUE_CATALOG_JARS

echo "JARs encontrados:"

find "$GLUE_JARS_DIR" \
    -maxdepth 1 \
    -type f \
    -name "*.jar" \
    -printf '%f\n'

# =========================================
# 9. VALIDAÇÃO DO AMBIENTE PYTHON
# =========================================

CURRENT_NOTEBOOK="Validação do ambiente Python"

echo
echo "Validando dependências..."

if [ ! -x "${VENV_PATH}/bin/python" ]; then

    echo "ERRO: Ambiente virtual não encontrado."

    exit 1

fi

if [ ! -x "${VENV_PATH}/bin/papermill" ]; then

    echo "ERRO: Papermill não instalado."

    exit 1

fi

if [ ! -x "${VENV_PATH}/bin/jupyter" ]; then

    echo "ERRO: Jupyter não instalado."

    exit 1

fi

"${VENV_PATH}/bin/python" <<'PY'

import pyspark
import boto3
import pandas
import papermill
import ipykernel

print("PySpark:", pyspark.__version__)
print("Boto3:", boto3.__version__)
print("Pandas:", pandas.__version__)
print("Papermill:", papermill.__version__)

print("Dependências Python validadas.")

PY

# =========================================
# 10. VALIDAÇÃO KERNEL
# =========================================

CURRENT_NOTEBOOK="Validação do kernel"

echo
echo "Validando kernel Jupyter..."

if ! "${VENV_PATH}/bin/jupyter" kernelspec list \
    | grep -q "$KERNEL_NAME"; then

    echo "ERRO: Kernel ${KERNEL_NAME} não registrado."

    exit 1

fi

echo "Kernel ${KERNEL_NAME} encontrado."

# =========================================
# 11. VALIDAÇÃO AWS STS E GLUE
# =========================================

CURRENT_NOTEBOOK="Validação de credenciais AWS e Glue"

echo
echo "Validando credenciais AWS..."

"${VENV_PATH}/bin/python" <<'PY'

import boto3
import os

region = os.environ["AWS_REGION"]

# STS
sts = boto3.client(
    "sts",
    region_name=region
)

identity = sts.get_caller_identity()

print("AWS Account:", identity["Account"])
print("AWS ARN:", identity["Arn"])

# Glue
glue = boto3.client(
    "glue",
    region_name=region
)

response = glue.get_databases(
    MaxResults=1
)

print("Comunicação com AWS Glue API estabelecida.")
print("Databases retornados:", len(response.get("DatabaseList", [])))

PY

# =========================================
# 12. VALIDAÇÃO DIRETÓRIOS
# =========================================

CURRENT_NOTEBOOK="Validação dos diretórios"

echo
echo "Validando diretórios..."

if [ ! -d "$NOTEBOOK_PATH" ]; then

    echo "ERRO: Diretório de notebooks não encontrado."

    exit 1

fi

if [ ! -f "${APP_PATH}/startup/00-spark-config.py" ]; then

    echo "ERRO: Configuração Spark não encontrada."

    exit 1

fi

if [ ! -r "${APP_PATH}/startup/00-spark-config.py" ]; then

    echo "ERRO: Configuração Spark não pode ser lida."

    exit 1

fi

# =========================================
# 13. ORDEM DOS NOTEBOOKS
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
# 14. VALIDAÇÃO DOS NOTEBOOKS
# =========================================

CURRENT_NOTEBOOK="Validação dos notebooks"

echo
echo "Verificando arquivos..."

for NOTEBOOK in "${NOTEBOOKS[@]}"; do

    INPUT="${NOTEBOOK_PATH}/${NOTEBOOK}"

    if [ ! -f "$INPUT" ]; then

        echo "ERRO: Notebook não encontrado:"

        echo "$INPUT"

        exit 1

    fi

done

echo "Todos os notebooks foram encontrados."

# =========================================
# 15. PREPARAÇÃO DA EXECUÇÃO
# =========================================

mkdir -p "$EXECUTION_OUTPUT"

echo
echo "========================================="
echo " G6 - DATA PROCESSING PIPELINE"
echo "========================================="

echo "Execução: ${EXECUTION_ID}"
echo "Início: ${PIPELINE_STARTED_AT}"
echo "Total de notebooks: ${TOTAL}"

echo "AWS Region: ${AWS_REGION}"
echo "Java Home: ${JAVA_HOME}"

echo "Resultados: ${EXECUTION_OUTPUT}"

echo "========================================="

# =========================================
# 16. EXECUÇÃO SEQUENCIAL
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

    "${VENV_PATH}/bin/papermill" \
        "$INPUT" \
        "$OUTPUT" \
        --kernel "$KERNEL_NAME" \
        -p execution_id "$EXECUTION_ID"

    echo
    echo "Notebook concluído: ${NOTEBOOK}"

    echo "Resultado: ${OUTPUT}"

    echo "Finalizado: $(date)"

done

CURRENT_NOTEBOOK="Finalização"

PIPELINE_FINISHED_AT=$(date)

echo
echo "========================================="
echo " PIPELINE CONCLUÍDO COM SUCESSO"
echo "========================================="

echo "Execução: ${EXECUTION_ID}"

echo "Notebooks executados: ${TOTAL}"

echo "Início: ${PIPELINE_STARTED_AT}"

echo "Finalização: ${PIPELINE_FINISHED_AT}"

echo "Resultados: ${EXECUTION_OUTPUT}"

echo "========================================="

exit 0