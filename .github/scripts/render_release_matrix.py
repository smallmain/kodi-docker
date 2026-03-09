#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

BEGIN_MARKER = "<!-- BEGIN GENERATED RELEASE MATRIX -->"
END_MARKER = "<!-- END GENERATED RELEASE MATRIX -->"


@dataclass(frozen=True)
class Release:
    release_version: str
    git_tag: str
    kodi_version: str
    published_at: str

    @property
    def sort_key(self) -> tuple[int, int, int]:
        return parse_semver(self.release_version)

    @property
    def published_date(self) -> str:
        try:
            normalized = self.published_at.replace("Z", "+00:00")
            parsed = datetime.fromisoformat(normalized)
        except ValueError:
            return self.published_at

        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)

        return parsed.astimezone(timezone.utc).date().isoformat()


def parse_semver(value: str) -> tuple[int, int, int]:
    parts = value.split(".")
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise ValueError(f"Expected release version in X.Y.Z format, got: {value}")
    return tuple(int(part) for part in parts)


def load_release_map(path: Path) -> tuple[str, list[Release]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    latest_release = data["latest_release"]
    releases: list[Release] = []
    seen_versions: set[str] = set()
    seen_tags: set[str] = set()

    for item in data["releases"]:
        release = Release(
            release_version=item["release_version"],
            git_tag=item.get("git_tag") or f"v{item['release_version']}",
            kodi_version=item["kodi_version"],
            published_at=item["published_at"],
        )

        if release.release_version in seen_versions:
            raise ValueError(f"Duplicate release version found: {release.release_version}")
        if release.git_tag in seen_tags:
            raise ValueError(f"Duplicate git tag found: {release.git_tag}")

        seen_versions.add(release.release_version)
        seen_tags.add(release.git_tag)
        parse_semver(release.release_version)
        releases.append(release)

    by_version = {release.release_version: release for release in releases}
    if latest_release not in by_version:
        raise ValueError(
            f"latest_release '{latest_release}' does not exist in {path.name}"
        )

    releases.sort(key=lambda release: release.sort_key, reverse=True)
    return latest_release, releases


def build_release_table(headers: tuple[str, str, str, str], rows: list[tuple[str, str, str, str]]) -> str:
    table_lines = [
        f"| {headers[0]} | {headers[1]} | {headers[2]} | {headers[3]} |",
        "| --- | --- | --- | --- |",
    ]
    table_lines.extend(
        f"| {tag} | {repo_release} | {kodi_version} | {published} |"
        for tag, repo_release, kodi_version, published in rows
    )
    return "\n".join(table_lines)


def render_english_section(latest_release: str, releases: list[Release]) -> str:
    by_version = {release.release_version: release for release in releases}
    latest = by_version[latest_release]
    rows = [
        (
            "`latest`",
            f"`{latest.git_tag}`",
            f"`{latest.kodi_version}`",
            latest.published_date,
        )
    ]
    rows.extend(
        (
            f"`{release.release_version}`",
            f"`{release.git_tag}`",
            f"`{release.kodi_version}`",
            release.published_date,
        )
        for release in releases
    )

    return "\n\n".join(
        [
            "## Image Tags And Kodi Versions",
            "`main` tracks direct builds from the `main` branch and is intentionally excluded from this table. `latest` always points to the newest numbered repository release. Numbered image tags such as `1.0.0` are repository release versions, not upstream Kodi versions.",
            build_release_table(
                ("Image tag", "Repository release", "Kodi version", "Published"),
                rows,
            ),
        ]
    )


def render_chinese_section(latest_release: str, releases: list[Release]) -> str:
    by_version = {release.release_version: release for release in releases}
    latest = by_version[latest_release]
    rows = [
        (
            "`latest`",
            f"`{latest.git_tag}`",
            f"`{latest.kodi_version}`",
            latest.published_date,
        )
    ]
    rows.extend(
        (
            f"`{release.release_version}`",
            f"`{release.git_tag}`",
            f"`{release.kodi_version}`",
            release.published_date,
        )
        for release in releases
    )

    return "\n\n".join(
        [
            "## 镜像标签与 Kodi 版本",
            "`main` 跟随 `main` 分支的直接构建，因此故意不放进这张表。`latest` 始终指向当前最新的编号 release。像 `1.0.0` 这样的编号表示仓库 release 版本，不是 Kodi 上游原生版本。",
            build_release_table(
                ("镜像标签", "仓库 Release", "Kodi 版本", "发布时间"),
                rows,
            ),
        ]
    )


def replace_generated_section(path: Path, rendered_section: str) -> bool:
    original = path.read_text(encoding="utf-8")
    updated = render_updated_text(original, rendered_section, path)

    if updated == original:
        return False

    path.write_text(updated, encoding="utf-8")
    return True


def render_updated_text(original: str, rendered_section: str, path: Path) -> str:
    pattern = re.compile(
        rf"{re.escape(BEGIN_MARKER)}.*?{re.escape(END_MARKER)}",
        re.DOTALL,
    )
    replacement = f"{BEGIN_MARKER}\n\n{rendered_section}\n\n{END_MARKER}"
    updated, replacements = pattern.subn(replacement, original)
    if replacements != 1:
        raise ValueError(
            f"Expected exactly one generated section in {path}, found {replacements}"
        )
    return updated


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render the generated release matrix section in both README files."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if rendering would change any README file.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    release_map = repo_root / ".github" / "kodi-release-map.json"
    readme_en = repo_root / "README.md"
    readme_zh = repo_root / "README.zh-CN.md"

    latest_release, releases = load_release_map(release_map)
    rendered_sections = {
        readme_en: render_english_section(latest_release, releases),
        readme_zh: render_chinese_section(latest_release, releases),
    }

    if args.check:
        stale_files: list[Path] = []
        for path, section in rendered_sections.items():
            original = path.read_text(encoding="utf-8")
            updated = render_updated_text(original, section, path)
            if updated != original:
                stale_files.append(path)

        if stale_files:
            print("Generated release matrix is out of date in:", file=sys.stderr)
            for path in stale_files:
                print(f"- {path.relative_to(repo_root)}", file=sys.stderr)
            return 1

        print("Generated release matrix is up to date.")
        return 0

    changed_files: list[Path] = []
    for path, section in rendered_sections.items():
        if replace_generated_section(path, section):
            changed_files.append(path)

    if changed_files:
        for path in changed_files:
            print(f"Updated {path.relative_to(repo_root)}")
    else:
        print("Release matrix already up to date.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
