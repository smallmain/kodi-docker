FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG KODI_VERSION=latest
ARG KODI_GIT_URL=https://github.com/xbmc/xbmc.git
ARG KODI_BUILD_JOBS=0
ARG KODI_BUILD_BINARY_ADDONS=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN set -eux; \
    sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      alsa-utils \
      ca-certificates \
      curl \
      dbus \
      fonts-arphic-uming \
      fonts-noto-cjk \
      fonts-wqy-microhei \
      git \
      gosu \
      jq \
      locales \
      mesa-utils \
      mesa-utils-extra \
      minidlna \
      pipewire \
      pipewire-pulse \
      pulseaudio-utils \
      software-properties-common \
      tini \
      tzdata \
      vainfo \
      wireplumber \
      xauth; \
    apt-get build-dep -y kodi; \
    apt-get install -y --no-install-recommends \
      libdisplay-info-dev \
      libgbm-dev \
      libinput-dev \
      libpcre3-dev \
      libwayland-dev \
      libxkbcommon-dev \
      wayland-protocols \
      waylandpp-dev; \
    rm -rf /var/lib/apt/lists/*; \
    locale-gen C.UTF-8

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN set -eux; \
    resolved_kodi_ref="${KODI_VERSION}"; \
    if [[ "${resolved_kodi_ref}" == "latest" ]]; then \
      resolved_kodi_ref="$(curl -fsSL https://api.github.com/repos/xbmc/xbmc/releases/latest | jq -r '.tag_name')"; \
    fi; \
    jobs="${KODI_BUILD_JOBS}"; \
    if [[ -z "${jobs}" || "${jobs}" == "0" ]]; then \
      jobs="$(nproc)"; \
    fi; \
    git clone --depth 1 --branch "${resolved_kodi_ref}" "${KODI_GIT_URL}" /usr/src/kodi; \
    cmake -S /usr/src/kodi -B /usr/src/kodi-build \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCORE_PLATFORM_NAME="x11 wayland gbm" \
      -DAPP_RENDER_SYSTEM=gl; \
    cmake --build /usr/src/kodi-build --parallel "${jobs}"; \
    cmake --install /usr/src/kodi-build; \
    if [[ "${KODI_BUILD_BINARY_ADDONS}" == "1" ]]; then \
      make -j"${jobs}" -C /usr/src/kodi/tools/depends/target/binary-addons PREFIX=/usr/local; \
    fi; \
    install -d /usr/local/share/kodi-build; \
    printf '%s\n' "${resolved_kodi_ref}" > /usr/local/share/kodi-build/kodi-ref; \
    chmod 0755 /usr/local/bin/entrypoint.sh; \
    mkdir -p /config /media; \
    rm -rf /usr/src/kodi /usr/src/kodi-build

ENV HOME=/config
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
WORKDIR /config

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
