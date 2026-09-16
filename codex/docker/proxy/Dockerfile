FROM python:3.13-slim

RUN pip install --no-cache-dir websockets==17.0.1

WORKDIR /app

COPY proxy.py .

ENTRYPOINT ["python", "proxy.py"]