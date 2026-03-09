[English](README.md) | **简体中文**

# Kodi Docker

在 Linux 上通过 Docker 运行 Kodi，并支持 HDMI 输出。镜像改为基于 Kodi 官方上游 release 源码构建，默认在构建时解析官方最新 tag，单镜像同时支持 X11、Wayland、DRM/GBM，默认编译官方二进制 add-on 集合，并默认开放常用远程控制端口，但不改动 Kodi 官方默认服务状态。

## 适用范围

- 仅支持 Linux 宿主机。
- macOS 和 Windows 不支持直接 HDMI 直通输出。
- DRM/GBM 模式面向本地 seat 或 VT/TTY 场景，宿主机仍需提供 `/dev/dri/card*`。
- 自行构建会比较重，因为 Kodi 和二进制 add-on 默认都从源码编译。

## 特性

- 基于 Kodi 官方上游源码构建，默认跟随最新正式 release
- 可通过 `.env` 和 Compose build args 控制 Kodi 版本
- 默认启用官方二进制 add-on 全量构建
- 单镜像，运行时可选显示后端：`x11`、`wayland`、`drm`
- 运行时可选音频后端：`alsa`、`pulseaudio`、`pipewire`
- DRM 覆盖层默认启用 `/run/udev`、高权限 capability 和放宽 seccomp
- `bridge` 模式下默认开放常用远程控制端口，同时保持 Kodi 官方默认服务状态，也保留 `host` 网络覆盖文件
- 支持通过 Mesa `llvmpipe` 回退到软件渲染

## 仓库结构

- `Dockerfile`：基于 Ubuntu 24.04，解析官方 Kodi release tag 并从源码构建
- [`docker/entrypoint.sh`](docker/entrypoint.sh)：运行时后端选择、执行文件解析与 UID/GID 映射
- `compose*.yaml`：基础 Compose 文件与各类覆盖文件
- `.github/workflows`：CI 与 GHCR 发布工作流

## 快速开始

1. 复制 `.env.example` 为 `.env`。
2. 默认使用 `IMAGE_NAME=ghcr.io/smallmain/kodi-docker`，除非你要切到自己发布的镜像仓库。
3. 把 `IMAGE_TAG` 设成你要部署的预构建镜像标签，例如 `main`、`latest` 或具体版本 tag。
4. 按宿主机环境修改 `LOCAL_UID`、`LOCAL_GID`、显示相关变量和运行时目录路径。
5. 用下面的 Compose 组合启动你需要的模式。

<!-- BEGIN GENERATED RELEASE MATRIX -->

## 镜像标签与 Kodi 版本

`main` 跟随 `main` 分支的直接构建，因此故意不放进这张表。`latest` 始终指向当前最新的编号 release。像 `1.0.0` 这样的编号表示仓库 release 版本，不是 Kodi 上游原生版本。

| 镜像标签 | 仓库 Release | Kodi 版本    | 发布时间   |
| -------- | ------------ | ------------ | ---------- |
| `latest` | `v1.0.0`     | `21.3-Omega` | 2026-03-09 |
| `1.0.0`  | `v1.0.0`     | `21.3-Omega` | 2026-03-09 |

<!-- END GENERATED RELEASE MATRIX -->

## Compose 分层

当前部署模型是 `compose.yaml` 加上若干覆盖文件。实际使用时，通常是固定带上基础层，再选一个显示层，按需叠加音频运行时层和网络层。

| 层级         | 是否必需 | 文件                         | 可选项                                     | 作用                                                                      |
| ------------ | -------- | ---------------------------- | ------------------------------------------ | ------------------------------------------------------------------------- |
| 基础层       | 是       | `compose.yaml`               | 固定一个                                   | 提供通用镜像、端口、`/config`、`/media`、`/dev/snd` 和基础环境变量        |
| 显示层       | 通常需要 | `compose.x11.yaml`           | `x11`                                      | 提供 X11 socket、Xauthority 挂载、`/dev/dri` 和 `KODI_VIDEO_BACKEND=x11`  |
| 显示层       | 通常需要 | `compose.wayland.yaml`       | `wayland`                                  | 提供 Wayland runtime 挂载、`/dev/dri` 和 `KODI_VIDEO_BACKEND=wayland`     |
| 显示层       | 通常需要 | `compose.drm.yaml`           | `drm`                                      | 提供 GBM/DRM 模式、`/dev/dri`、`/dev/input`、`/run/udev` 和高兼容权限设置 |
| 音频运行时层 | 可选     | `compose.audio-runtime.yaml` | 非 Wayland 下的 `pulseaudio` 或 `pipewire` | 挂载宿主机 runtime 目录，并导出 `PULSE_SERVER` / `XDG_RUNTIME_DIR`        |
| 网络层       | 可选     | `compose.network-host.yaml`  | `host`                                     | 从 bridge 端口映射切换到 host 网络                                        |

组合规则：

- 先从 `compose.yaml` 开始。
- 正常部署时只选一个显示层。
- 只有当所选音频后端依赖宿主机 runtime 目录，且显示层本身没有提供时，才额外叠加 `compose.audio-runtime.yaml`。
- 只有当 bridge 模式不够用时，才叠加 `compose.network-host.yaml`。

## Compose 示例

### X11 + ALSA

首次运行前，先允许容器访问你的 X Server：

```bash
xhost +local:docker
cp .env.example .env
docker compose -f compose.yaml -f compose.x11.yaml pull
docker compose -f compose.yaml -f compose.x11.yaml up -d
```

### Wayland + PipeWire

`compose.wayland.yaml` 已经挂载宿主机运行时目录，所以常见情况下不需要再叠加 `compose.audio-runtime.yaml`。

```bash
cp .env.example .env
sed -i 's/^KODI_VIDEO_BACKEND=.*/KODI_VIDEO_BACKEND=wayland/' .env
sed -i 's/^KODI_AUDIO_BACKEND=.*/KODI_AUDIO_BACKEND=pipewire/' .env
docker compose -f compose.yaml -f compose.wayland.yaml pull
docker compose -f compose.yaml -f compose.wayland.yaml up -d
```

### DRM + PipeWire

当你要用 DRM 视频输出加 PipeWire 音频时，需要把 `compose.drm.yaml` 和 `compose.audio-runtime.yaml` 叠加起来。`compose.drm.yaml` 本身是偏“兼容优先”的模式：默认挂 `/run/udev`，启用 `privileged`、`SYS_ADMIN`、`SYS_RAWIO`，并放宽 seccomp。

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

### 使用 Host 网络

如果你希望 Kodi 直接使用宿主机网络栈，避免后续再考虑额外端口，或者需要更好的局域网发现兼容性，可以叠加 `compose.network-host.yaml`。下面示例基于最常见的 X11 组合：

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

## 自行构建

上面的章节默认都是在部署 GHCR 预构建镜像。只有你明确要自己编译 Kodi 时，才使用这一节。

```bash
docker compose build
docker compose up -d
```

或者直接对某个组合执行构建并启动：

```bash
docker compose -f compose.yaml -f compose.x11.yaml up -d --build
```

## 变量矩阵

这张表可以直接对应 `.env`。`必填` 表示该部署方式下必须设置；`条件必填` 表示只有在特定后端或覆盖层下才需要。

| 变量                       | 类型         | 必填性   | 默认值                          | 何时设置 / 说明                                                    |
| -------------------------- | ------------ | -------- | ------------------------------- | ------------------------------------------------------------------ |
| `KODI_VERSION`             | 构建变量     | 可选     | `latest`                        | 本地构建时使用的 Kodi 源码版本；可写成官方精确 tag                 |
| `KODI_BUILD_BINARY_ADDONS` | 构建变量     | 可选     | `1`                             | 设为 `0` 可加快本地 smoke build                                    |
| `KODI_BUILD_JOBS`          | 构建变量     | 可选     | `0`                             | `0` 表示本地构建时自动使用全部 CPU 核心                            |
| `IMAGE_TAG`                | 通用环境变量 | 建议设置 | `main`                          | 选择预构建镜像标签，如 `main`、`latest` 或 release tag             |
| `LOCAL_UID`                | 通用环境变量 | 建议设置 | `1000`                          | 建议改成宿主机用户 UID，避免 `/config` 和运行时文件权限不一致      |
| `LOCAL_GID`                | 通用环境变量 | 建议设置 | `1001`                          | 建议改成宿主机用户 GID                                             |
| `DISPLAY`                  | 通用环境变量 | 条件必填 | `:0`                            | 使用 `compose.x11.yaml` 时需要                                     |
| `XAUTHORITY`               | 通用环境变量 | 条件必填 | `/home/your-user/.Xauthority`   | 使用 X11 且依赖 Xauthority 鉴权时需要                              |
| `WAYLAND_DISPLAY`          | 通用环境变量 | 条件必填 | `wayland-0`                     | 使用 `compose.wayland.yaml` 时需要，除非 compositor 正好也是默认值 |
| `HOST_XDG_RUNTIME_DIR`     | 通用环境变量 | 条件必填 | `/run/user/1000`                | Wayland 或 `compose.audio-runtime.yaml` 场景需要                   |
| `KODI_VIDEO_BACKEND`       | 通用环境变量 | 可选     | `x11`                           | `x11`、`wayland`、`drm`，应与所选显示层一致                        |
| `KODI_AUDIO_BACKEND`       | 通用环境变量 | 可选     | `alsa`                          | `alsa`、`pulseaudio`、`pipewire`                                   |
| `KODI_HTTP_PORT`           | 通用环境变量 | 可选     | `8080`                          | Kodi Web Server 的宿主机映射端口                                   |
| `KODI_JSONRPC_PORT`        | 通用环境变量 | 可选     | `9090`                          | 远程控制客户端使用的 TCP 端口映射                                  |
| `KODI_EVENTSERVER_PORT`    | 通用环境变量 | 可选     | `9777`                          | EventServer 的 UDP 端口映射                                        |
| `KODI_SSDP_PORT`           | 通用环境变量 | 可选     | `1900`                          | UPnP/SSDP 发现流量的 UDP 端口映射                                  |
| `TZ`                       | 通用环境变量 | 可选     | `UTC`                           | 容器时区                                                           |
| `KODI_RENDERER`            | 通用环境变量 | 可选     | `auto`                          | 设为 `software` 可强制使用 Mesa `llvmpipe`                         |
| `KODI_EXTRA_ARGS`          | 通用环境变量 | 可选     | 空                              | 额外追加到 Kodi 启动命令的参数                                     |
| `KODI_EXECUTABLE`          | 通用环境变量 | 可选     | 空                              | 必要时手动指定要启动的 Kodi 可执行文件                             |
| `KODI_DRY_RUN`             | 通用环境变量 | 可选     | `0`                             | 设为 `1` 时只打印最终命令，不真正启动                              |
| `IMAGE_NAME`               | 通用环境变量 | 可选     | `ghcr.io/smallmain/kodi-docker` | 只有在你发布了自己的 fork 镜像时才需要改                           |

## 默认端口

`bridge` 模式下，Compose 默认开放这些常用端口：

- `8080/tcp`
- `9090/tcp`
- `9777/udp`
- `1900/udp`

Kodi 本身对新建 profile 仍保持官方默认服务状态。这里预开放端口只是为了让用户后续在 Kodi 内启用 Web Server、EventServer 或发现类功能时，不需要重建容器。

## 软件渲染

镜像内置软件渲染路径。设置 `KODI_RENDERER=software` 后，入口脚本会导出：

- `LIBGL_ALWAYS_SOFTWARE=1`
- `GALLIUM_DRIVER=llvmpipe`

这不会移除显示输出和音频输出对宿主机后端的依赖，只是把容器内的 Mesa 渲染改为软件模式。

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
  ghcr.io/smallmain/kodi-docker:main
```

## 常见问题

- 如果本地或 CI 的自行构建太慢，可以临时把 `KODI_BUILD_BINARY_ADDONS=0`。
- 如果 X11 报权限或授权错误，先确认是否执行了 `xhost +local:docker`，并检查 `XAUTHORITY` 是否指向当前会话的 Xauthority 文件。
- 如果 PulseAudio 或 PipeWire 无法连接，确认 `LOCAL_UID/GID` 与宿主机当前用户一致，并且 `HOST_XDG_RUNTIME_DIR` 指向正确的运行时目录，例如 `/run/user/1000` 或 `/run/user/0`。
- 如果 DRM 模式黑屏或没有输入，检查 `/dev/dri`、`/dev/input`、`/run/udev` 是否存在，并尽量从本地 VT 启动，而不是在已有桌面会话中抢占同一个终端。
- 如果硬件渲染异常，先试 `KODI_RENDERER=software`，把 GPU 驱动问题和显示后端问题分开排查。

## CI 与发布

- PR 和推送到 `main` 时会执行 shell、Dockerfile、Compose 和镜像 smoke build 校验。
- CI 的 smoke build 会关闭二进制 add-on 编译，避免验证耗时过长。
- 每天会有一个自动化流程检查 Kodi 上游 release；一旦发现新的正式版，就会创建新的仓库编号 release，并同步刷新双语 README 中生成的版本对照表。
- 推送到 `main` 会发布 `ghcr.io/<owner>/kodi-docker:main`。
- 推送符合 `v*` 的 tag 会按照 `.github/kodi-release-map.json` 中记录的精确 Kodi 版本重建 `ghcr.io/<owner>/kodi-docker:X.Y.Z`。
- `latest` 始终跟随版本对照表中标记为当前最新的编号 release。

## 参考来源

- [Kodi 官方最新 release API](https://api.github.com/repos/xbmc/xbmc/releases/latest)
- [Kodi Debian/Ubuntu 构建指南](https://raw.githubusercontent.com/xbmc/xbmc/master/docs/README.Ubuntu.md)
- [Kodi Linux 构建指南](https://raw.githubusercontent.com/xbmc/xbmc/master/docs/README.Linux.md)

## 许可证

MIT，详见 [LICENSE](LICENSE)。
