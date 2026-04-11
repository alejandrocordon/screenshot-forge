FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY sizes.py resizer.py forge.py forge_web.py ./
COPY templates/ templates/

RUN mkdir -p /data/input /data/output

EXPOSE 8642

ENTRYPOINT ["python", "forge.py"]
CMD ["-i", "/data/input", "-o", "/data/output"]
