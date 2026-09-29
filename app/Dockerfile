FROM python:3.10-slim
WORKDIR /
COPY app/servidor.py .
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 5000
CMD ["uvicorn", "servidor:app", "--host", "0.0.0.0", "--port", "5000"]