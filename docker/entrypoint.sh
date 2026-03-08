#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[entrypoint] %s\n' "$*"
}

die() {
  printf '[entrypoint] error: %s\n' "$*" >&2
  exit 1
}

require_integer() {
  local name="$1"
  local value="$2"

  [[ "$value" =~ ^[0-9]+$ ]] || die "${name} must be an integer, got: ${value}"
}

ensure_group_gid() {
  local target_gid="$1"
  local existing_group
  local current_gid

  if getent group "${target_gid}" >/dev/null 2>&1; then
    existing_group="$(getent group "${target_gid}" | cut -d: -f1)"
    printf '%s' "${existing_group}"
  elif getent group kodi >/dev/null 2>&1; then
    current_gid="$(getent group kodi | cut -d: -f3)"
    if [[ "${current_gid}" != "${target_gid}" ]]; then
      groupmod -o -g "${target_gid}" kodi
    fi
    printf 'kodi'
  else
    groupadd -o -g "${target_gid}" kodi
    printf 'kodi'
  fi
}

ensure_user_uid_gid() {
  local target_uid="$1"
  local target_group="$2"

  if id kodi >/dev/null 2>&1; then
    usermod -o -u "${target_uid}" -g "${target_group}" -d /config -M -s /usr/sbin/nologin kodi
  else
    useradd -o -u "${target_uid}" -g "${target_group}" -d /config -M -s /usr/sbin/nologin kodi
  fi
}

add_device_group() {
  local path="$1"
  local fallback_name="$2"
  local gid
  local group_name

  [[ -e "${path}" ]] || return 0
  gid="$(stat -c '%g' "${path}" 2>/dev/null || true)"
  [[ -n "${gid}" ]] || return 0

  group_name="$(getent group "${gid}" | cut -d: -f1 || true)"
  if [[ -z "${group_name}" ]]; then
    group_name="${fallback_name}"
    if ! getent group "${group_name}" >/dev/null 2>&1; then
      groupadd -o -g "${gid}" "${group_name}" >/dev/null 2>&1 || true
    fi
  fi

  usermod -a -G "${group_name}" kodi >/dev/null 2>&1 || true
}

print_command() {
  local -a argv=("$@")

  printf '[entrypoint] command:'
  printf ' %q' "${argv[@]}"
  printf '\n'
}

resolve_kodi_executable() {
  local backend="$1"
  local explicit_executable="${KODI_EXECUTABLE:-}"
  local -a candidates=()
  local candidate

  if [[ -n "${explicit_executable}" ]]; then
    if command -v "${explicit_executable}" >/dev/null 2>&1; then
      printf '%s' "${explicit_executable}"
      return 0
    fi
    die "KODI_EXECUTABLE is set but not found in PATH: ${explicit_executable}"
  fi

  case "${backend}" in
    x11)
      candidates=(kodi-x11 kodi)
      ;;
    wayland)
      candidates=(kodi-wayland kodi)
      ;;
    drm)
      candidates=(kodi-gbm kodi-standalone kodi)
      ;;
    *)
      die "unsupported backend while resolving Kodi executable: ${backend}"
      ;;
  esac

  for candidate in "${candidates[@]}"; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      printf '%s' "${candidate}"
      return 0
    fi
  done

  die "unable to find a Kodi executable for backend ${backend}; tried: ${candidates[*]}"
}

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

KODI_VIDEO_BACKEND="${KODI_VIDEO_BACKEND:-x11}"
KODI_AUDIO_BACKEND="${KODI_AUDIO_BACKEND:-alsa}"
KODI_RENDERER="${KODI_RENDERER:-auto}"
KODI_EXTRA_ARGS="${KODI_EXTRA_ARGS:-}"
KODI_DRY_RUN="${KODI_DRY_RUN:-0}"
KODI_EXECUTABLE="${KODI_EXECUTABLE:-}"
LOCAL_UID="${LOCAL_UID:-}"
LOCAL_GID="${LOCAL_GID:-}"
WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

case "${KODI_VIDEO_BACKEND}" in
  x11|wayland|drm)
    ;;
  *)
    die "KODI_VIDEO_BACKEND must be one of: x11, wayland, drm"
    ;;
esac

case "${KODI_AUDIO_BACKEND}" in
  alsa|pulseaudio|pipewire)
    ;;
  *)
    die "KODI_AUDIO_BACKEND must be one of: alsa, pulseaudio, pipewire"
    ;;
esac

case "${KODI_RENDERER}" in
  auto|software)
    ;;
  *)
    die "KODI_RENDERER must be one of: auto, software"
    ;;
esac

case "${KODI_DRY_RUN}" in
  0|1)
    ;;
  *)
    die "KODI_DRY_RUN must be 0 or 1"
    ;;
esac

mkdir -p /config /media
export HOME=/config

if [[ "${KODI_VIDEO_BACKEND}" == "x11" ]]; then
  [[ -n "${DISPLAY:-}" ]] || die "DISPLAY must be set for x11 mode"
  if [[ -f /tmp/.docker.xauth ]]; then
    export XAUTHORITY=/tmp/.docker.xauth
  fi
fi

if [[ "${KODI_AUDIO_BACKEND}" == "pulseaudio" && -z "${PULSE_SERVER:-}" && -S /tmp/host-runtime/pulse/native ]]; then
  export PULSE_SERVER=unix:/tmp/host-runtime/pulse/native
fi

if [[ "${KODI_AUDIO_BACKEND}" == "pipewire" && -z "${XDG_RUNTIME_DIR:-}" && -d /tmp/host-runtime ]]; then
  export XDG_RUNTIME_DIR=/tmp/host-runtime
fi

if [[ "${KODI_RENDERER}" == "software" ]]; then
  export LIBGL_ALWAYS_SOFTWARE=1
  export GALLIUM_DRIVER=llvmpipe
fi

declare -a kodi_args
resolved_kodi_executable="$(resolve_kodi_executable "${KODI_VIDEO_BACKEND}")"
kodi_args=("${resolved_kodi_executable}")

case "${KODI_VIDEO_BACKEND}" in
  x11)
    if [[ "${resolved_kodi_executable}" == "kodi" ]]; then
      kodi_args+=(--windowing=x11)
    fi
    ;;
  wayland)
    if [[ "${resolved_kodi_executable}" == "kodi" ]]; then
      kodi_args+=(--windowing=wayland)
    fi
    ;;
  drm)
    if [[ "${resolved_kodi_executable}" == "kodi" ]]; then
      kodi_args+=(--windowing=gbm --standalone)
    fi
    ;;
esac

kodi_args+=("--audio-backend=${KODI_AUDIO_BACKEND}")

if [[ -n "${KODI_EXTRA_ARGS}" ]]; then
  # shellcheck disable=SC2206
  extra_args=( ${KODI_EXTRA_ARGS} )
  kodi_args+=("${extra_args[@]}")
fi

if [[ -n "${LOCAL_UID}" || -n "${LOCAL_GID}" ]]; then
  runtime_group=""
  LOCAL_UID="${LOCAL_UID:-1000}"
  LOCAL_GID="${LOCAL_GID:-1001}"
  require_integer "LOCAL_UID" "${LOCAL_UID}"
  require_integer "LOCAL_GID" "${LOCAL_GID}"
  runtime_group="$(ensure_group_gid "${LOCAL_GID}")"
  ensure_user_uid_gid "${LOCAL_UID}" "${runtime_group}"
  chown "${LOCAL_UID}:${LOCAL_GID}" /config /media >/dev/null 2>&1 || true
  add_device_group /dev/snd kodi-audio
  add_device_group /dev/dri kodi-video
  add_device_group /dev/input kodi-input
fi

log "video backend: ${KODI_VIDEO_BACKEND}"
log "audio backend: ${KODI_AUDIO_BACKEND}"
log "renderer: ${KODI_RENDERER}"
log "executable: ${resolved_kodi_executable}"

if [[ "${KODI_DRY_RUN}" == "1" ]]; then
  print_command "${kodi_args[@]}"
  exit 0
fi

if [[ -n "${LOCAL_UID}" || -n "${LOCAL_GID}" ]]; then
  exec gosu "kodi:${runtime_group}" "${kodi_args[@]}"
fi

log "LOCAL_UID/LOCAL_GID not set; running Kodi as root for compatibility"
exec "${kodi_args[@]}"
