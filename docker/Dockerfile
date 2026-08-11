FROM python:3.12-slim

# gcc is needed only to compile the netifaces dependency, then removed
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev \
    && pip install --no-cache-dir \
        tahoe-lafs \
        "pyopenssl==24.2.1" \
        "cryptography<44" \
        "service-identity==24.2.0" \
    && apt-get purge -y gcc libc6-dev \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY check.py /check.py
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
