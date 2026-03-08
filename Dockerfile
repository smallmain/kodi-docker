FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    gosu \
    kodi \
    libasound2 \
    libdrm2 \
    libegl1 \
    libgbm1 \
    libgl1-mesa-dri \
    libgles2 \
    libpipewire-0.3-0 \
    libpulse0 \
    libwayland-client0 \
    libwayland-egl1 \
    libx11-6 \
    libxext6 \
    libxkbcommon0 \
    libxrandr2 \
    mesa-utils \
    pipewire \
    pulseaudio-utils \
    tini \
    xauth \
  && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
  && mkdir -p /config /media

ENV HOME=/config
WORKDIR /config

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
