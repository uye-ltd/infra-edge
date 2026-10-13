# Static security analyzer for the rendered nginx config (used by nginx-t.sh).
FROM python:3.12-alpine
RUN pip install --no-cache-dir gixy-ng==0.2.55
ENTRYPOINT ["gixy"]
