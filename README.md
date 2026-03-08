# kodi-docker

Run Kodi in Docker with HDMI output on Linux. The image supports X11, Wayland, and DRM/GBM display backends, ALSA/PulseAudio/PipeWire audio backends, software rendering fallback through Mesa `llvmpipe`, and both `bridge` and `host` networking.

## Scope

- Linux hosts only.
- macOS and Windows are not supported for direct HDMI output.
- DRM/GBM mode is intended for a local seat or VT/TTY session and still requires `/dev/dri/card*` on the host.

## Features

- Single image, runtime-selectable display backend: `x11`, `wayland`, `drm`
- Runtime-selectable audio backend: `alsa`, `pulseaudio`, `pipewire`
- Software rendering fallback: `KODI_RENDERER=software`
- Default `bridge` networking with an override for `host`
- Compose-first workflow with `docker run` examples

## Repository Layout

- `Dockerfile`: Debian Bookworm based Kodi image
- [`docker/entrypoint.sh`](docker/entrypoint.sh): runtime backend selection and user mapping
- `compose*.yaml`: Compose base file and override files
- `.github/workflows`: CI and GHCR publishing

## Quick Start

1. Copy `.env.example` to `.env`.
2. Adjust `LOCAL_UID`, `LOCAL_GID`, display variables, and runtime directory paths for your host.
3. Start the combination you need with the Compose overrides below.

## Compose Examples

### X11 + ALSA

Before the first run, allow the container to talk to your X server:

```bash
xhost +local:docker
cp .env.example .env
docker compose -f compose.yaml -f compose.x11.yaml up -d
```

### Wayland + PipeWire

`compose.wayland.yaml` already mounts the host runtime directory, so PipeWire works without `compose.audio-runtime.yaml` in the common case.

```bash
cp .env.example .env
sed -i 's/^KODI_VIDEO_BACKEND=.*/KODI_VIDEO_BACKEND=wayland/' .env
sed -i 's/^KODI_AUDIO_BACKEND=.*/KODI_AUDIO_BACKEND=pipewire/' .env
docker compose -f compose.yaml -f compose.wayland.yaml up -d
```

### DRM + ALSA

Run this on a Linux host with a local seat. Avoid sharing the same VT with an active desktop session.

```bash
cp .env.example .env
sed -i 's/^KODI_VIDEO_BACKEND=.*/KODI_VIDEO_BACKEND=drm/' .env
docker compose -f compose.yaml -f compose.drm.yaml up -d
```

### Host Networking

Add `compose.network-host.yaml` when you need stronger compatibility for mDNS, UPnP, or other LAN discovery flows.

```bash
docker compose \
  -f compose.yaml \
  -f compose.x11.yaml \
  -f compose.network-host.yaml \
  up -d
```

### X11 + PulseAudio

Use `compose.audio-runtime.yaml` when you need the host runtime directory for PulseAudio or PipeWire outside Wayland mode.

```bash
cp .env.example .env
sed -i 's/^KODI_AUDIO_BACKEND=.*/KODI_AUDIO_BACKEND=pulseaudio/' .env
docker compose \
  -f compose.yaml \
  -f compose.x11.yaml \
  -f compose.audio-runtime.yaml \
  up -d
```

## Runtime Variables

| Variable | Values | Default | Notes |
| --- | --- | --- | --- |
| `KODI_VIDEO_BACKEND` | `x11`, `wayland`, `drm` | `x11` | `drm` maps to Kodi GBM standalone mode |
| `KODI_AUDIO_BACKEND` | `alsa`, `pulseaudio`, `pipewire` | `alsa` | Maps to Kodi `--audio-backend=` |
| `KODI_RENDERER` | `auto`, `software` | `auto` | `software` enables Mesa `llvmpipe` |
| `KODI_EXTRA_ARGS` | shell-style CLI args | empty | Appended to the Kodi command |
| `KODI_DRY_RUN` | `0`, `1` | `0` | Prints the generated command and exits |
| `LOCAL_UID` | integer | `1000` in Compose | When set, the entrypoint creates/adjusts a `kodi` user |
| `LOCAL_GID` | integer | `1000` in Compose | Same behavior as `LOCAL_UID` |

## Software Rendering

Software rendering is built into the image. When you set `KODI_RENDERER=software`, the entrypoint exports:

- `LIBGL_ALWAYS_SOFTWARE=1`
- `GALLIUM_DRIVER=llvmpipe`

This does not require users to install `llvmpipe` on the host. It only changes how Mesa renders inside the container. Display and audio prerequisites still come from the selected host backend.

Important limits:

- `software` replaces GPU 3D rendering, not HDMI scanout.
- `drm + software` still requires a working `/dev/dri/card*` on the host for KMS/HDMI output.
- `x11` and `wayland` still require a running X server or Wayland compositor.

## Network Modes

- `bridge` is the default. Use it when normal port publishing is enough.
- `host` removes the explicit `8080`, `9090`, and `9777/udp` mappings and gives Kodi better compatibility with LAN discovery protocols.

## docker run Example

```bash
docker run --rm \
  --device /dev/snd \
  --device /dev/dri \
  -e DISPLAY="$DISPLAY" \
  -e XAUTHORITY=/tmp/.docker.xauth \
  -e LOCAL_UID="$(id -u)" \
  -e LOCAL_GID="$(id -g)" \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$XAUTHORITY:/tmp/.docker.xauth:ro" \
  -v "$PWD/config:/config" \
  -v "$PWD/media:/media" \
  ghcr.io/your-org/kodi-docker:main
```

## Troubleshooting

- If X11 fails with authorization errors, confirm `xhost +local:docker` and verify `XAUTHORITY` points to your active Xauthority file.
- If PulseAudio or PipeWire cannot connect, confirm `LOCAL_UID/GID` match the host user and `HOST_XDG_RUNTIME_DIR` points to the active runtime directory such as `/run/user/1000`.
- If DRM mode opens a black screen or no input, verify `/dev/dri` and `/dev/input` are present and start Kodi from a local VT rather than an existing desktop session.
- If hardware rendering fails, try `KODI_RENDERER=software` first to isolate GPU driver issues from display backend issues.

## CI and Publishing

- Pull requests and pushes to `main` run shell, Dockerfile, Compose, and smoke-build checks.
- Pushes to `main` publish `ghcr.io/<owner>/kodi-docker:main`.
- Tags matching `v*` publish `ghcr.io/<owner>/kodi-docker:vX.Y.Z` and `latest`.

## License

MIT. See [LICENSE](LICENSE).
