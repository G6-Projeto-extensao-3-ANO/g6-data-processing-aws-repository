from fastapi import FastAPI
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response
import time

app = FastAPI(title="Data Processing API")

REQUEST_COUNT = Counter(
    "fastapi_requests_total",
    "Total de requisições recebidas pela API",
    ["method", "endpoint", "status"]
)

REQUEST_LATENCY = Histogram(
    "fastapi_request_duration_seconds",
    "Tempo de processamento das requisições",
    ["method", "endpoint"]
)

REQUESTS_IN_PROGRESS = Gauge(
    "fastapi_requests_in_progress",
    "Número de requisições atualmente em processamento",
    ["method", "endpoint"]
)

# Exemplo de métrica específica da aplicação
DATA_PROCESSED = Counter(
    "data_processing_total",
    "Quantidade de dados processados"
)

@app.middleware("http")
async def prometheus_middleware(request, call_next):

    start_time = time.time()
    method = request.method
    endpoint = request.url.path
    REQUESTS_IN_PROGRESS.labels(
        method=method,
        endpoint=endpoint
    ).inc()

    try:
        response = await call_next(request)
        status = str(response.status_code)
        REQUEST_COUNT.labels(
            method=method,
            endpoint=endpoint,
            status=status
        ).inc()

        return response

    finally:
        duration = time.time() - start_time
        REQUEST_LATENCY.labels(
            method=method,
            endpoint=endpoint
        ).observe(duration)
        REQUESTS_IN_PROGRESS.labels(
            method=method,
            endpoint=endpoint
        ).dec()


@app.get("/")
async def root():

    DATA_PROCESSED.inc()

    return {
        "message": "Data Processing API funcionando"
    }

@app.get("/metrics")
async def metrics():

    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )