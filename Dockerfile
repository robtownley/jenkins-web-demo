FROM nginx:stable-alpine

COPY site/index.html /usr/share/nginx/html/index.html

RUN printf 'healthy\n' > /usr/share/nginx/html/healthz

HEALTHCHECK --interval=2s --timeout=2s --start-period=5s --retries=10 \
    CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
