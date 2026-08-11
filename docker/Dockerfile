FROM python:3.12-slim

RUN pip install --no-cache-dir \
    tahoe-lafs \
    "pyopenssl==24.2.1" \
    "cryptography<44" \
    "service-identity==24.2.0"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
