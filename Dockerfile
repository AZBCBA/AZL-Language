# AZL language — native engine + repo tree for staging-style runs.
# Build: docker build -t azl-language .
# Run (example): docker run --rm -p 8080:8080 -e AZL_BUILD_API_PORT=8080 azl-language
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    gcc \
    iproute2 \
    jq \
    libc6-dev \
    openssl \
    ripgrep \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/azl

COPY . .

RUN mkdir -p .azl/bin \
  && gcc -O2 -Wall -Wextra -o .azl/bin/azl-native-engine tools/azl_native_engine.c \
  && chmod +x .azl/bin/azl-native-engine

ENV AZL_NATIVE_ONLY=1 \
    AZL_STRICT=1 \
    AZL_ENABLE_LEGACY_HOST=0

EXPOSE 8080 8787

CMD ["bash", "scripts/start_azl_native_mode.sh"]
