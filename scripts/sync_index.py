#!/usr/bin/env python3
"""
sync_index.py — генерация index.yaml из .lua плагинов.

Источник правды — .lua файлы. index.yaml полностью перегенерируется.
Нет .lua → нет записи в индексе.

Языковые папки определяются автоматически — любая папка в корне репо
у которой есть .lua файлы. Никакого хардкода языков.
"""

import os, re, sys, subprocess
from pathlib import Path

# ── Конфиг ────────────────────────────────────────────────────────────────────

RAW_BASE  = "https://raw.githubusercontent.com/{repo}/main"
SKIP_DIRS = {".git", ".github", "scripts", "icons"}

# ── Автодетект языковых папок ─────────────────────────────────────────────────

def find_lang_dirs(root: Path) -> list[str]:
    """Возвращает папки в корне у которых есть .lua файлы, по алфавиту."""
    result = []
    for d in sorted(root.iterdir()):
        if not d.is_dir():
            continue
        if d.name in SKIP_DIRS or d.name.startswith("."):
            continue
        if any(d.glob("*.lua")):
            result.append(d.name)
    return result

def get_lang_meta(lang_dir: str, dir_path: Path) -> tuple[str, str]:
    """
    Возвращает (lang_code, lang_name).
    Читает из существующего index.yaml если есть — иначе имя папки как fallback.
    """
    index_path = dir_path / "index.yaml"
    if index_path.exists():
        text = index_path.read_text(encoding="utf-8-sig")
        code_m = re.search(r'^language:\s*"([^"]+)"', text, re.MULTILINE)
        name_m = re.search(r'^name:\s*"([^"]+)"', text, re.MULTILINE)
        code = code_m.group(1) if code_m else lang_dir
        name = name_m.group(1) if name_m else lang_dir.capitalize()
        return code, name
    return lang_dir, lang_dir.capitalize()

# ── Репо ──────────────────────────────────────────────────────────────────────

def get_repo() -> str:
    repo = os.environ.get("GITHUB_REPOSITORY", "").strip()
    if repo:
        return repo
    try:
        remote = subprocess.check_output(
            ["git", "remote", "get-url", "origin"], stderr=subprocess.DEVNULL
        ).decode().strip()
        m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", remote)
        if m:
            return m.group(1)
    except Exception:
        pass
    print("[ERROR] Не удалось определить репозиторий. Задайте GITHUB_REPOSITORY=owner/repo")
    sys.exit(1)

# ── Парсинг .lua ──────────────────────────────────────────────────────────────

def parse_lua(filepath: Path) -> dict | None:
    try:
        text = filepath.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    except Exception as e:
        print(f"  [WARN] Не удалось прочитать {filepath.name}: {e}")
        return None

    def field(key):
        m = re.search(rf'^{key}\s*=\s*"([^"]+)"', text, re.MULTILINE)
        return m.group(1).strip() if m else None

    plugin_id = field("id")
    version   = field("version")
    if not plugin_id or not version:
        print(f"  [WARN] {filepath.name}: нет id или version — пропускаем")
        return None

    return {
        "id":      plugin_id,
        "name":    field("name") or plugin_id,
        "version": version,
        "icon":    field("icon") or "",
    }

# ── Генерация index.yaml ──────────────────────────────────────────────────────

def build_lang_index(plugins: list[dict], lang_code: str, lang_name: str) -> str:
    lines = [
        f'language: "{lang_code}"',
        f'name: "{lang_name}"',
        'sources:',
    ]
    for p in plugins:
        lines += [
            f'  - id: "{p["id"]}"',
            f'    name: "{p["name"]}"',
            f'    version: "{p["version"]}"',
            f'    url: "{p["url"]}"',
            f'    icon: "{p["icon"]}"',
            f'    language: "{lang_code}"',
        ]
    return "\n".join(lines) + "\n"

def build_root_index(langs: list[dict], raw_base: str) -> str:
    """langs — список {"dir": str, "code": str, "name": str}"""
    lines = ["languages:"]
    for lang in langs:
        lines += [
            f'  {lang["dir"]}:',
            f'    name: "{lang["name"]}"',
            f'    url: "{raw_base}/{lang["dir"]}/index.yaml"',
        ]
    return "\n".join(lines) + "\n"

# ── Главная логика ────────────────────────────────────────────────────────────

def sync(root: Path):
    repo     = get_repo()
    raw_base = RAW_BASE.format(repo=repo)
    print(f"Репозиторий : {repo}")
    print(f"Raw base    : {raw_base}\n")

    lang_dirs = find_lang_dirs(root)
    if not lang_dirs:
        print("[WARN] Не найдено ни одной папки с .lua файлами.")
        return

    langs_meta = []  # для корневого индекса

    for lang_dir in lang_dirs:
        dir_path  = root / lang_dir
        lua_files = sorted(dir_path.glob("*.lua"))
        lang_code, lang_name = get_lang_meta(lang_dir, dir_path)

        print(f"── {lang_dir}/ ({len(lua_files)} плагинов) ──")

        plugins = []
        for lua_file in lua_files:
            meta = parse_lua(lua_file)
            if not meta:
                continue
            icon = meta["icon"] or f"{raw_base}/icons/{meta['id']}.png"
            plugins.append({
                "id":      meta["id"],
                "name":    meta["name"],
                "version": meta["version"],
                "url":     f"{raw_base}/{lang_dir}/{lua_file.name}",
                "icon":    icon,
            })
            print(f"  {meta['id']} v{meta['version']}")

        index_path = dir_path / "index.yaml"
        new_text   = build_lang_index(plugins, lang_code, lang_name)
        old_text   = index_path.read_text(encoding="utf-8") if index_path.exists() else ""

        if new_text != old_text:
            index_path.write_text(new_text, encoding="utf-8")
            print(f"  → {lang_dir}/index.yaml обновлён")
        else:
            print(f"  → без изменений")

        langs_meta.append({"dir": lang_dir, "code": lang_code, "name": lang_name})
        print()

    # Корневой index.yaml
    root_index = root / "index.yaml"
    new_root   = build_root_index(langs_meta, raw_base)
    old_root   = root_index.read_text(encoding="utf-8") if root_index.exists() else ""

    print("── index.yaml (корневой) ──")
    if new_root != old_root:
        root_index.write_text(new_root, encoding="utf-8")
        print("  → обновлён")
    else:
        print("  → без изменений")

if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    sync(root.resolve())