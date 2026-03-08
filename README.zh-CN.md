# kodi-docker

在 Linux 上通过 Docker 运行 Kodi，并支持 HDMI 输出。镜像支持 X11、Wayland、DRM/GBM 三种显示后端，ALSA、PulseAudio、PipeWire 三种音频后端，支持通过 Mesa `llvmpipe` 回退到软件渲染，也支持 `bridge` 和 `host` 两种网络模式。

## 适用范围

- 仅支持 Linux 宿主机。
- macOS 和 Windows 不支持直接 HDMI 直通输出。
- DRM/GBM 模式面向本地 seat 或 VT/TTY 场景，宿主机仍需提供 `/dev/dri/card*`。

## 特性

- 单镜像，运行时可选显示后端：`x11`、`wayland`、`drm`
- 运行时可选音频后端：`alsa`、`pulseaudio`、`pipewire`
- 软件渲染回退：`KODI_RENDERER=software`
- 默认 `bridge` 网络，并提供 `host` 覆盖文件
- 以 Docker Compose 为主，也提供 `docker run` 示例

## 仓库结构

- `Dockerfile`：基于 Debian Bookworm 的 Kodi 镜像
- [`docker/entrypoint.sh`](docker/entrypoint.sh)：运行时后端选择与 UID/GID 映射
- `compose*.yaml`：基础 Compose 文件与各类覆盖文件
- `.github/workflows`：CI 与 GHCR 发布工作流

## 快速开始

1. 复制 `.env.example` 为 `.env`。
2. 按宿主机环境修改 `LOCAL_UID`、`LOCAL_GID`、显示相关变量和运行时目录路径。
3. 用下面的 Compose 组合启动你需要的模式。

## Compose 示例

### X11 + ALSA

首次运行前，先允许容器访问你的 X Server：

```bash
xhost +local:docker
cp .env.example .env
docker compose -f compose.yaml -f compose.x11.yaml up -d
```

### Wayland + PipeWire

`compose.wayland.yaml` 已经挂载宿主机运行时目录，所以常见情况下不需要再叠加 `compose.audio-runtime.yaml`。

```bash
cp .env.example .env
sed -i 's/^KODI_VIDEO_BACKEND=.*/KODI_VIDEO_BACKEND=wayland/' .env
sed -i 's/^KODI_AUDIO_BACKEND=.*/KODI_AUDIO_BACKEND=pipewire/' .env
docker compose -f compose.yaml -f compose.wayland.yaml up -d
```

### DRM + ALSA

请在具备本地 seat 的 Linux 宿主机上运行，避免与现有桌面会话共享同一个 VT。

```bash
cp .env.example .env
sed -i 's/^KODI_VIDEO_BACKEND=.*/KODI_VIDEO_BACKEND=drm/' .env
docker compose -f compose.yaml -f compose.drm.yaml up -d
```

### Host 网络

如果你需要更好的 mDNS、UPnP 或局域网设备发现兼容性，叠加 `compose.network-host.yaml`：

```bash
docker compose \
  -f compose.yaml \
  -f compose.x11.yaml \
  -f compose.network-host.yaml \
  up -d
```

### X11 + PulseAudio

当你在非 Wayland 模式下使用 PulseAudio 或 PipeWire 时，请叠加 `compose.audio-runtime.yaml`：

```bash
cp .env.example .env
sed -i 's/^KODI_AUDIO_BACKEND=.*/KODI_AUDIO_BACKEND=pulseaudio/' .env
docker compose \
  -f compose.yaml \
  -f compose.x11.yaml \
  -f compose.audio-runtime.yaml \
  up -d
```

## 运行时变量

| 变量 | 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `KODI_VIDEO_BACKEND` | `x11`、`wayland`、`drm` | `x11` | `drm` 会映射为 Kodi 的 GBM standalone 模式 |
| `KODI_AUDIO_BACKEND` | `alsa`、`pulseaudio`、`pipewire` | `alsa` | 映射到 Kodi `--audio-backend=` |
| `KODI_RENDERER` | `auto`、`software` | `auto` | `software` 会启用 Mesa `llvmpipe` |
| `KODI_EXTRA_ARGS` | shell 风格参数串 | 空 | 直接追加到 Kodi 命令 |
| `KODI_DRY_RUN` | `0`、`1` | `0` | 打印最终命令后退出 |
| `LOCAL_UID` | 整数 | Compose 中默认 `1000` | 设置后入口脚本会创建或调整 `kodi` 用户 |
| `LOCAL_GID` | 整数 | Compose 中默认 `1000` | 与 `LOCAL_UID` 配套使用 |

## 软件渲染

镜像内置软件渲染路径。设置 `KODI_RENDERER=software` 后，入口脚本会导出：

- `LIBGL_ALWAYS_SOFTWARE=1`
- `GALLIUM_DRIVER=llvmpipe`

用户不需要在宿主机额外安装 `llvmpipe`。它只影响容器内 Mesa 的渲染方式，显示输出和音频输出前提仍由宿主机后端决定。

需要注意：

- `software` 只替代 GPU 3D 渲染，不替代 HDMI 扫描输出。
- `drm + software` 仍然要求宿主机存在可用的 `/dev/dri/card*`。
- `x11` 和 `wayland` 仍然要求宿主机已有可用的 X Server 或 Wayland compositor。

## 网络模式

- `bridge` 是默认模式，适合常规端口映射场景。
- `host` 会移除显式的 `8080`、`9090`、`9777/udp` 端口映射，并提升局域网发现协议兼容性。

## docker run 示例

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

## 常见问题

- 如果 X11 报权限或授权错误，先确认是否执行了 `xhost +local:docker`，并检查 `XAUTHORITY` 是否指向当前会话的 Xauthority 文件。
- 如果 PulseAudio 或 PipeWire 无法连接，确认 `LOCAL_UID/GID` 与宿主机当前用户一致，并且 `HOST_XDG_RUNTIME_DIR` 指向正确的运行时目录，例如 `/run/user/1000`。
- 如果 DRM 模式黑屏或没有输入，检查 `/dev/dri` 与 `/dev/input` 是否存在，并尽量从本地 VT 启动，而不是在已有桌面会话中抢占同一个终端。
- 如果硬件渲染异常，先试 `KODI_RENDERER=software`，把 GPU 驱动问题和显示后端问题分开排查。

## CI 与发布

- PR 和推送到 `main` 时会执行 shell、Dockerfile、Compose 和镜像 smoke build 校验。
- 推送到 `main` 会发布 `ghcr.io/<owner>/kodi-docker:main`。
- 推送符合 `v*` 的 tag 会发布 `ghcr.io/<owner>/kodi-docker:vX.Y.Z` 和 `latest`。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
