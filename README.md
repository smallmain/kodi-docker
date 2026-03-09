**English** | [简体中文](README.zh-CN.md)

# Kodi Docker

Run Kodi in Docker with Linux HDMI output. The image is built from the official upstream Kodi release source, defaults to the latest official tag at build time, ships X11, Wayland, and DRM/GBM in one image, builds the official binary add-on tree by default, and publishes the common remote-control ports without changing Kodi's official service defaults.

## Scope

- Linux hosts only.
- macOS and Windows are not supported for direct HDMI output.
- DRM/GBM mode is intended for a local seat or VT/TTY session and still requires `/dev/dri/card*` on the host.
- Local builds are intentionally heavy because Kodi and its binary add-ons are compiled from source.

## Features

- Official upstream Kodi source build, defaulting to the latest release tag at build time
- Build-time version control through `.env` and Compose build args
- Full-feature image with official binary add-ons enabled by default
- Single image, runtime-selectable display backend: `x11`, `wayland`, `drm`
- Runtime-selectable audio backend: `alsa`, `pulseaudio`, `pipewire`
- Aggressive DRM compatibility profile with `/run/udev`, extra capabilities, and relaxed seccomp
- Common remote-control ports published in bridge mode while keeping Kodi's official default service state, plus an optional host-network override
- Software rendering fallback through Mesa `llvmpipe`

## Repository Layout

- `Dockerfile`: Ubuntu 24.04 image that resolves an official Kodi release tag and builds Kodi from source
- [`docker/entrypoint.sh`](docker/entrypoint.sh): runtime backend selection, executable resolution, and user mapping
- `compose*.yaml`: Compose base file and override files
- `.github/workflows`: CI and GHCR publishing

## Quick Start

1. Copy `.env.example` to `.env`.
2. Keep `IMAGE_NAME=ghcr.io/smallmain/kodi-docker` unless you publish a fork under a different registry path.
3. Set `IMAGE_TAG` to the prebuilt image you want to run, such as `main`, `latest`, or an exact release tag.
4. Adjust `LOCAL_UID`, `LOCAL_GID`, display variables, and runtime directory paths for your host.
5. Start the combination you need with the Compose overrides below.

<!-- BEGIN GENERATED RELEASE MATRIX -->

## Image Tags And Kodi Versions

`main` tracks direct builds from the `main` branch and is intentionally excluded from this table. `latest` always points to the newest numbered repository release. Numbered image tags such as `1.0.0` are repository release versions, not upstream Kodi versions.

| Image tag | Repository release | Kodi version | Published  |
| --------- | ------------------ | ------------ | ---------- |
| `latest`  | `v1.0.0`           | `21.3-Omega` | 2026-03-09 |
| `1.0.0`   | `v1.0.0`           | `21.3-Omega` | 2026-03-09 |

<!-- END GENERATED RELEASE MATRIX -->

## Compose Layers

The deployment model is `compose.yaml` plus zero or more override files. In practice, users usually choose one display layer, optionally add one audio-runtime layer, and optionally add one network layer.

| Layer         | Required    | File                         | Choices                                    | Purpose                                                                                |
| ------------- | ----------- | ---------------------------- | ------------------------------------------ | -------------------------------------------------------------------------------------- |
| Base          | Yes         | `compose.yaml`               | exactly one                                | Common image, ports, `/config`, `/media`, `/dev/snd`, and environment defaults         |
| Display       | Usually yes | `compose.x11.yaml`           | `x11`                                      | X11 socket, Xauthority mount, `/dev/dri`, `KODI_VIDEO_BACKEND=x11`                     |
| Display       | Usually yes | `compose.wayland.yaml`       | `wayland`                                  | Wayland runtime mount, `/dev/dri`, `KODI_VIDEO_BACKEND=wayland`                        |
| Display       | Usually yes | `compose.drm.yaml`           | `drm`                                      | GBM/DRM mode, `/dev/dri`, `/dev/input`, `/run/udev`, privileged compatibility settings |
| Audio Runtime | Optional    | `compose.audio-runtime.yaml` | `pulseaudio` or `pipewire` outside Wayland | Mounts host runtime dir and exports `PULSE_SERVER` / `XDG_RUNTIME_DIR`                 |
| Network       | Optional    | `compose.network-host.yaml`  | `host`                                     | Switches from bridge publishing to host networking                                     |

Rules of thumb:

- Start with `compose.yaml`.
- Add exactly one display layer in normal deployments.
- Add `compose.audio-runtime.yaml` only when the chosen audio backend needs the host runtime directory and the display layer does not already provide it.
- Add `compose.network-host.yaml` only when bridge mode is not enough for your discovery or LAN-control needs.

## Compose Examples

### X11 + ALSA

Before the first run, allow the container to talk to your X server:

```bash
xhost +local:docker
cp .env.example .env
docker compose -f compose.yaml -f compose.x11.yaml pull
docker compose -f compose.yaml -f compose.x11.yaml up -d
```

### Wayland + PipeWire

`compose.wayland.yaml` already mounts the host runtime directory, so PipeWire works without `compose.audio-runtime.yaml` in the common case.

```bash
cp .env.example .env
sed -i 's/^KODI_VIDEO_BACKEND=.*/KODI_VIDEO_BACKEND=wayland/' .env
sed -i 's/^KODI_AUDIO_BACKEND=.*/KODI_AUDIO_BACKEND=pipewire/' .env
docker compose -f compose.yaml -f compose.wayland.yaml pull
docker compose -f compose.yaml -f compose.wayland.yaml up -d
```

### DRM + PipeWire

Combine `compose.drm.yaml` with `compose.audio-runtime.yaml` when you want DRM video output and PipeWire audio on the host runtime socket. `compose.drm.yaml` intentionally trades away isolation for compatibility. It mounts `/run/udev`, runs privileged, adds `SYS_ADMIN` and `SYS_RAWIO`, and disables seccomp filtering.

```bash
cp .env.example .env
sed -i 's/^KODI_VIDEO_BACKEND=.*/KODI_VIDEO_BACKEND=drm/' .env
sed -i 's/^KODI_AUDIO_BACKEND=.*/KODI_AUDIO_BACKEND=pipewire/' .env
docker compose \
  -f compose.yaml \
  -f compose.drm.yaml \
  -f compose.audio-runtime.yaml \
  pull
docker compose \
  -f compose.yaml \
  -f compose.drm.yaml \
  -f compose.audio-runtime.yaml \
  up -d
```

### Use Host Networking

Add `compose.network-host.yaml` when you want Kodi to use the host network stack directly for LAN discovery flows and any ports you enable later inside Kodi. This example shows it on top of the common X11 deployment.

```bash
cp .env.example .env
docker compose \
  -f compose.yaml \
  -f compose.x11.yaml \
  -f compose.network-host.yaml \
  pull
docker compose \
  -f compose.yaml \
  -f compose.x11.yaml \
  -f compose.network-host.yaml \
  up -d
```

## Build Locally

The sections above assume you deploy the prebuilt GHCR image. Only use this path when you want to compile Kodi yourself instead of pulling `ghcr.io/smallmain/kodi-docker`.

```bash
docker compose build
docker compose up -d
```

Or build and start a specific combination directly:

```bash
docker compose -f compose.yaml -f compose.x11.yaml up -d --build
```

## Variable Matrix

Use this table as the source of truth for `.env`. `Required` means you must set it for the relevant deployment mode; `Conditional` means it is only needed for specific backends or overrides.

| Variable                   | Type       | Required    | Default                         | When to set / Notes                                                                      |
| -------------------------- | ---------- | ----------- | ------------------------------- | ---------------------------------------------------------------------------------------- |
| `KODI_VERSION`             | Build      | Optional    | `latest`                        | Build-time Kodi source version; use an exact upstream tag to pin builds                  |
| `KODI_BUILD_BINARY_ADDONS` | Build      | Optional    | `1`                             | Set `0` to speed up local smoke builds                                                   |
| `KODI_BUILD_JOBS`          | Build      | Optional    | `0`                             | `0` means use all available CPU cores during local builds                                |
| `IMAGE_TAG`                | Common Env | Recommended | `main`                          | Select the prebuilt image tag such as `main`, `latest`, or a release tag                 |
| `LOCAL_UID`                | Common Env | Recommended | `1000`                          | Match the host user ID so `/config` and runtime files are owned correctly                |
| `LOCAL_GID`                | Common Env | Recommended | `1001`                          | Match the host group ID                                                                  |
| `DISPLAY`                  | Common Env | Conditional | `:0`                            | Required for `compose.x11.yaml`                                                          |
| `XAUTHORITY`               | Common Env | Conditional | `/home/your-user/.Xauthority`   | Required for X11 deployments that rely on Xauthority auth                                |
| `WAYLAND_DISPLAY`          | Common Env | Conditional | `wayland-0`                     | Required for `compose.wayland.yaml` unless your compositor already uses the default name |
| `HOST_XDG_RUNTIME_DIR`     | Common Env | Conditional | `/run/user/1000`                | Required for Wayland and for `compose.audio-runtime.yaml`                                |
| `KODI_VIDEO_BACKEND`       | Common Env | Optional    | `x11`                           | `x11`, `wayland`, or `drm`; should match the display layer you selected                  |
| `KODI_AUDIO_BACKEND`       | Common Env | Optional    | `alsa`                          | `alsa`, `pulseaudio`, or `pipewire`                                                      |
| `KODI_HTTP_PORT`           | Common Env | Optional    | `8080`                          | Host-side published port for Kodi web server                                             |
| `KODI_JSONRPC_PORT`        | Common Env | Optional    | `9090`                          | Host-side published TCP port used by remote-control clients                              |
| `KODI_EVENTSERVER_PORT`    | Common Env | Optional    | `9777`                          | Host-side published UDP port for EventServer                                             |
| `KODI_SSDP_PORT`           | Common Env | Optional    | `1900`                          | Host-side published UDP port for UPnP/SSDP discovery                                     |
| `TZ`                       | Common Env | Optional    | `UTC`                           | Container timezone                                                                       |
| `KODI_RENDERER`            | Common Env | Optional    | `auto`                          | Set `software` to force Mesa `llvmpipe`                                                  |
| `KODI_EXTRA_ARGS`          | Common Env | Optional    | empty                           | Extra CLI arguments appended to the Kodi command                                         |
| `KODI_EXECUTABLE`          | Common Env | Optional    | empty                           | Override the auto-detected launcher if you need a specific Kodi binary                   |
| `KODI_DRY_RUN`             | Common Env | Optional    | `0`                             | Set `1` to print the final command and exit                                              |
| `IMAGE_NAME`               | Common Env | Optional    | `ghcr.io/smallmain/kodi-docker` | Change only if you publish a fork to another registry path                               |

## Default Ports

Bridge-mode Compose publishes these common ports by default:

- `8080/tcp`
- `9090/tcp`
- `9777/udp`
- `1900/udp`

Kodi itself keeps the official default service state for fresh profiles. The published ports are there so that if a user later enables Web server, EventServer, or discovery features inside Kodi, the container does not need to be rebuilt.

## Software Rendering

Software rendering is built into the image. When you set `KODI_RENDERER=software`, the entrypoint exports:

- `LIBGL_ALWAYS_SOFTWARE=1`
- `GALLIUM_DRIVER=llvmpipe`

This does not remove the host-side requirements for display or audio backends. It only changes how Mesa renders inside the container.

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
  ghcr.io/smallmain/kodi-docker:main
```

## Troubleshooting

- If a local build is too slow for CI or testing, set `KODI_BUILD_BINARY_ADDONS=0` temporarily.
- If X11 fails with authorization errors, confirm `xhost +local:docker` and verify `XAUTHORITY` points to your active Xauthority file.
- If PulseAudio or PipeWire cannot connect, confirm `LOCAL_UID/GID` match the host user and `HOST_XDG_RUNTIME_DIR` points to the active runtime directory such as `/run/user/1000` or `/run/user/0`.
- If DRM mode opens a black screen or no input, verify `/dev/dri`, `/dev/input`, and `/run/udev` are present and start Kodi from a local VT rather than an existing desktop session.
- If hardware rendering fails, try `KODI_RENDERER=software` first to isolate GPU driver issues from display backend issues.

## CI And Publishing

- Pull requests and pushes to `main` run shell, Dockerfile, Compose, and smoke-build checks.
- CI smoke builds disable binary add-on compilation to keep verification time reasonable.
- A daily automation checks the upstream Kodi release feed, creates a new numbered repository release when needed, and refreshes the generated release matrix in both README files.
- Pushes to `main` publish `ghcr.io/<owner>/kodi-docker:main`.
- Tags matching `v*` rebuild `ghcr.io/<owner>/kodi-docker:X.Y.Z` from the exact Kodi version recorded in `.github/kodi-release-map.json`.
- `latest` always points to the numbered release recorded as current latest in the generated release matrix.

## Sources

- [Official Kodi release feed](https://api.github.com/repos/xbmc/xbmc/releases/latest)
- [Kodi Debian/Ubuntu build guide](https://raw.githubusercontent.com/xbmc/xbmc/master/docs/README.Ubuntu.md)
- [Kodi Linux build guide](https://raw.githubusercontent.com/xbmc/xbmc/master/docs/README.Linux.md)

## License

MIT. See [LICENSE](LICENSE).
