# Contributing

## Development

1. Copy `.env.example` to `.env` and adjust host-specific values.
2. Use Docker Compose overrides to match your display and audio stack.
3. Run `docker compose config` for the combinations you change before opening a PR.

## Pull requests

- Keep changes focused.
- Update both `README.md` and `README.zh-CN.md` when behavior changes.
- Do not add host-specific secrets or absolute local paths to the repository.

## CI expectations

- Shell scripts must pass `shellcheck`.
- The Dockerfile must pass `hadolint`.
- Compose files must remain mergeable across the documented combinations.
