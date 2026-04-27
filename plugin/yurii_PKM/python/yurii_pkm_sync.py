#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from datetime import datetime
from typing import Iterable

# ---------------------------------------------------------------------------
# Regex
# ---------------------------------------------------------------------------
LINK_RE    = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
FIXED_LINK_TEXT_MARKER = "pkm:fixed-text"
TITLE_RE   = re.compile(r'^title:\s*(.*)$', re.IGNORECASE)
FILETYPE_RE = re.compile(r'^filetype:\s*(.*)$', re.IGNORECASE)
H1_RE      = re.compile(r'^#\s+(.+)$')
SEP_RE     = re.compile(r'^_{3,}\s*$')
SECTION_NAMES = {"up", "down", "branch", "back", "backlink"}



def bare_section_name(text: str) -> str:
    stripped = text.strip()
    stripped = re.sub(r'^#+\s*', '', stripped)
    return stripped.lower()


def is_section_header(text: str, name: str) -> bool:
    section = bare_section_name(text)
    target = name.lower()
    if target in {"back", "backlink"}:
        return section in {"back", "backlink"}
    return section == target


def is_markdown_file(path: Path) -> bool:
    return path.suffix.lower() == '.md'


def is_t_note(path: Path) -> bool:
    return path.stem.startswith('T_')


def has_yaml_front_matter(lines: list[str]) -> bool:
    if not lines:
        return False
    if lines[0].strip() != '---':
        return False
    for line in lines[1:]:
        if line.strip() == '---':
            return True
    return False


def is_expand_generated_t_note(path: Path, lines: list[str] | None = None) -> bool:
    if not is_t_note(path):
        return False
    if lines is None:
        lines = read_lines(path)
    return not has_yaml_front_matter(lines)

# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

def read_lines(path: Path) -> list[str]:
    if not is_markdown_file(path):
        return []
    return path.read_text(encoding="utf-8").splitlines()


def write_lines(path: Path, lines: list[str]) -> None:
    text = "\n".join(lines)
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text, encoding="utf-8")


def note_title(lines: list[str], path: Path) -> str:
    in_yaml = False
    yaml_done = False
    for line in lines[:40]:
        stripped = line.strip()
        if stripped == "---":
            if not in_yaml:
                in_yaml = True
            else:
                in_yaml = False
                yaml_done = True
            continue
        if in_yaml:
            m = TITLE_RE.match(line)
            if m:
                return m.group(1).strip() or path.stem
        if not in_yaml:
            m = H1_RE.match(line)
            if m:
                return m.group(1).strip()
    return path.stem


def note_filetype(lines: list[str], path: Path) -> str:
    in_yaml = False
    for line in lines[:40]:
        stripped = line.strip()
        if stripped == "---":
            in_yaml = not in_yaml
            continue
        if not in_yaml:
            continue
        m = FILETYPE_RE.match(line)
        if m:
            value = m.group(1).strip().upper()
            return value[:1] if value else ""

    stem = path.stem
    if "_" in stem:
        return stem.split("_", 1)[0].upper()[:1]
    return ""


def find_section(lines: list[str], name: str) -> tuple[int, int]:
    """Return (start_index, end_index) of *name* section.

    start_index points to the section-header line itself.
    end_index points to the next section header (or len(lines)).
    Returns (-1, -1) when not found.
    """
    target = name.lower()
    candidates: list[int] = []
    in_fence = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
        if not in_fence and is_section_header(stripped, target):
            candidates.append(i)
    if not candidates:
        return (-1, -1)
    start = candidates[-1]
    end = len(lines)
    in_fence = False
    for j in range(start + 1, len(lines)):
        stripped = lines[j].strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
        if not in_fence and bare_section_name(stripped) in SECTION_NAMES:
            end = j
            break
    return (start, end)


def section_content(lines: list[str], name: str) -> list[str]:
    start, end = find_section(lines, name)
    if start < 0:
        return []
    return lines[start + 1: end]


def replace_section(lines: list[str], name: str, new_content: list[str]) -> list[str]:
    start, end = find_section(lines, name)
    if start < 0:
        lines = list(lines) + ["# " + name.capitalize()]
        start = len(lines) - 1
        end = len(lines)
    return lines[: start + 1] + new_content + lines[end:]


def remove_section(lines: list[str], name: str) -> list[str]:
    start, end = find_section(lines, name)
    if start < 0:
        return list(lines)
    new_lines = lines[:start] + lines[end:]
    while len(new_lines) >= 2 and new_lines[-1] == "" and new_lines[-2] == "":
        new_lines.pop()
    return new_lines


def ensure_sections(lines: list[str]) -> list[str]:
    if find_section(lines, "up")[0] < 0:
        lines = list(lines) + ["# Up"]
    if find_section(lines, "backlink")[0] < 0:
        lines = list(lines) + ["", "# BackLink"]

    return lines


def parse_links(lines: list[str]) -> list[tuple[str, str]]:
    """Return [(text, target), ...] from lines, skipping ___-separated content."""
    result = []
    for line in lines:
        if SEP_RE.match(line):
            break
        for text, target in LINK_RE.findall(line):
            result.append((text, target))
    return result


def outbound_links_from_down(lines: list[str]) -> list[tuple[str, str]]:
    """Collect markdown links from Down section (or legacy Branch)."""
    result: list[tuple[str, str]] = []
    down_start, down_end = find_section(lines, "down")
    if down_start < 0:
        down_start, down_end = find_section(lines, "branch")
    if down_start < 0:
        return result

    in_fence = False
    for line in lines[down_start + 1: down_end]:
        stripped = line.strip()

        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        if SEP_RE.match(stripped):
            break

        for text, target in LINK_RE.findall(line):
            result.append((text, target))

    return result


def outbound_links_for_backlink(lines: list[str]) -> list[tuple[str, str]]:
    """Collect markdown links from body text (exclude Up/Down/BackLink sections)."""
    result: list[tuple[str, str]] = []
    in_yaml = False
    in_fence = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if i == 0 and stripped == "---":
            in_yaml = True
            continue
        if in_yaml:
            if stripped == "---":
                in_yaml = False
            continue

        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if SEP_RE.match(stripped):
            break
        if (is_section_header(stripped, "up")
                or is_section_header(stripped, "down")
                or is_section_header(stripped, "branch")
                or is_section_header(stripped, "back")
                or is_section_header(stripped, "backlink")):
            break

        for text, target in LINK_RE.findall(line):
            result.append((text, target))
    return result


def sort_back_links(link_lines: list[str], from_dir: Path, include_index: bool = True) -> list[str]:
    """Sort Back section links into category/note blocks based on target filetype."""
    note_links: list[tuple[datetime, str]] = []
    category_links: list[tuple[datetime, str]] = []
    index_line = "[Index](index.md)"

    def sort_datetime(target_path: Path) -> datetime:
        stem = target_path.stem
        if "_" in stem:
            _, ts = stem.split("_", 1)
            if re.fullmatch(r"\d{12}", ts):
                try:
                    return datetime.strptime(ts, "%y%m%d%H%M%S")
                except ValueError:
                    pass

        lines = read_lines(target_path)
        in_yaml = False
        for line in lines[:40]:
            stripped = line.strip()
            if stripped == "---":
                in_yaml = not in_yaml
                continue
            if not in_yaml:
                continue
            if stripped.lower().startswith("time:"):
                value = stripped.split(":", 1)[1].strip().strip('"\'')
                for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
                    try:
                        return datetime.strptime(value, fmt)
                    except ValueError:
                        pass

        try:
            return datetime.fromtimestamp(target_path.stat().st_mtime)
        except OSError:
            return datetime.min

    for line in link_lines:
        m = re.search(r'\(([^)]+)\)', line)
        if not m:
            continue
        target = m.group(1).strip()
        fname = target.split('/')[-1]
        if fname.lower() == 'index.md':
            index_line = line
            continue

        target_path = (from_dir / target).resolve()
        target_type = get_filetype(target_path)
        dt = sort_datetime(target_path)
        if target_type == "K":
            category_links.append((dt, line))
        else:
            note_links.append((dt, line))

    category_links.sort(key=lambda x: x[0], reverse=True)
    note_links.sort(key=lambda x: x[0], reverse=True)

    result: list[str] = []
    if category_links:
        result.append("category:")
        result.extend(line for _, line in category_links)
    if note_links:
        if result:
            result.append("")
        result.extend(line for _, line in note_links)
    if include_index:
        if result:
            result.append("")

        result.append(index_line)
    return result


def build_back(parent_paths: list[Path], note_path: Path, existing_lines: list[str]) -> list[str]:
    """Build Back section content from parent paths."""
    from_dir = note_path.parent
    include_index = note_path.name != 'index.md'

    existing_index = ''
    for line in existing_lines:
        m = re.search(r'\(([^)]+)\)', line)
        if m and m.group(1).strip().split('/')[-1] == 'index.md':
            existing_index = line
            break

    deduped_parents: list[Path] = []
    seen: set[Path] = set()
    for parent in parent_paths:
        rp = parent.resolve()
        if rp == note_path.resolve() or rp in seen:
            continue
        seen.add(rp)
        deduped_parents.append(rp)

    raw = [make_link_line(p, get_title(p), from_dir) for p in deduped_parents]
    result = sort_back_links(raw, from_dir, include_index=include_index)

    if include_index and existing_index and result and result[-1].lower().startswith('[index]'):
        result[-1] = existing_index

    return result


def make_link_line(target_path: Path, title: str, from_dir: Path) -> str:
    try:
        rel = target_path.relative_to(from_dir)
        rel_str = rel.as_posix()
    except ValueError:
        rel_str = target_path.name
    text = title if title else target_path.stem
    return f"[{text}]({rel_str})"


def create_f_and_link(current_file: Path, root: Path) -> Path:
    """Legacy helper kept for compatibility.

    Creates a new F note and inserts its link just before the current file's Back section.
    """
    current_file = current_file.resolve()
    root = root.resolve()

    ts = datetime.now().strftime("%y%m%d%H%M%S")
    f_name = f"F_{ts}.md"
    f_path = root / f_name

    content = [
        "---",
        f"time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "title: ",
        "---",
        "",
        "# ",
        "",
        "",
        "",
        "# BackLink",
        "[index](index.md)",
    ]
    root.mkdir(parents=True, exist_ok=True)
    write_lines(f_path, content)

    lines = ensure_sections(read_lines(current_file))
    back_start, _ = find_section(lines, "back")
    insert_at = back_start if back_start >= 0 else len(lines)

    rel = f_path.relative_to(current_file.parent).as_posix()
    link_line = f"[{f_path.stem}]({rel})"
    new_lines = list(lines)
    if link_line not in new_lines:
        new_lines.insert(insert_at, link_line)
        write_lines(current_file, new_lines)

    return f_path


# ---------------------------------------------------------------------------
# Title cache
# ---------------------------------------------------------------------------

_title_cache: dict[Path, str] = {}
_filetype_cache: dict[Path, str] = {}

def get_title(path: Path) -> str:
    path = path.resolve()
    if not is_markdown_file(path):
        return ""
    if path in _title_cache:
        return _title_cache[path]
    if not path.exists():
        return ""
    lines = read_lines(path)
    t = note_title(lines, path)
    _title_cache[path] = t
    return t


def get_filetype(path: Path) -> str:
    path = path.resolve()
    if not is_markdown_file(path) or not path.exists():
        return ""
    if path in _filetype_cache:
        return _filetype_cache[path]
    lines = read_lines(path)
    t = note_filetype(lines, path)
    _filetype_cache[path] = t
    return t


# ---------------------------------------------------------------------------
# update_titles_in_file
#   - markdown リンクの表示テキストを最新タイトルに更新
#   - branch/back 内でファイルが存在しないリンクを削除
#   - ___ 以降は処理しない
# ---------------------------------------------------------------------------

def update_titles_in_file(path: Path) -> bool:
    """Rewrite markdown link text to note titles in one file. Return True if changed."""
    lines = read_lines(path)
    base = path.parent
    result: list[str] = []
    modified = False
    in_branch = False
    in_back = False
    after_sep = False
    in_fence = False

    for line in lines:
        stripped = line.strip()

        if stripped.startswith("```"):
            in_fence = not in_fence

        if not in_fence:
            if is_section_header(stripped, "branch"):
                in_branch, in_back, after_sep = True, False, False
                result.append(line)
                continue
            if is_section_header(stripped, "back"):
                in_branch, in_back, after_sep = False, True, False
                result.append(line)
                continue
            if SEP_RE.match(line):
                after_sep = True
                result.append(line)
                continue

        if after_sep or in_fence:
            result.append(line)
            continue

        m = re.match(r'^\s*(\[([^\]]+)\]\(([^)]+)\))\s*$', line)
        if not m:
            result.append(line)
            continue

        link_text = m.group(2)
        target_text = m.group(3)

        if link_text != Path(target_text).stem:
            # 手動で付けた表示名は保持（stem一致のみ自動更新対象）
            result.append(line)
            continue

        if '\x00' in target_text:
            result.append(line)
            continue

        target = (base / target_text).resolve()
        if not is_markdown_file(target):
            result.append(line)
            continue

        if not target.exists():
            if in_branch or in_back:
                # 存在しないファイルへのリンクは branch/back では削除
                modified = True
                continue
            result.append(line)
            continue

        title = get_title(target)
        text = title if title else Path(target_text).stem
        prefix_ws = re.match(r'^\s*', line).group(0)
        suffix_ws = re.search(r'\s*$', line).group(0)
        new_line = f"{prefix_ws}[{text}]({target_text}){suffix_ws}"
        if new_line != line:
            modified = True
            line = new_line
        result.append(line)

    if modified:
        write_lines(path, result)
    return modified


# ---------------------------------------------------------------------------
# update_up_sections (full scan: Down -> Up propagation)
# ---------------------------------------------------------------------------

def iter_notes(root: Path) -> Iterable[Path]:
    for path in sorted(root.rglob("*.md")):
        if path.is_file() and ".undo" not in path.parts:
            yield path


def up_targets(lines: list[str], note_path: Path) -> set[Path]:
    targets: set[Path] = set()
    for _, target in parse_links(section_content(lines, "up")):
        if "\x00" in target:
            continue
        resolved = (note_path.parent / target).resolve()
        if is_markdown_file(resolved):
            targets.add(resolved)
    return targets


def update_up_sections(root: Path) -> int:
    """Scan all notes; rebuild BackLink from body links."""

    root = root.resolve()
    all_paths = list(iter_notes(root))

    backlinks_children_of: dict[Path, list[Path]] = {}
    lines_map: dict[Path, list[str]] = {}

    for p in all_paths:
        lines = read_lines(p)
        if p.name != 'index.md' and not is_expand_generated_t_note(p, lines):
            lines = ensure_sections(lines)
        lines_map[p] = lines
        body_kids: list[Path] = []
        body_seen: set[Path] = set()
        for _, target in outbound_links_for_backlink(lines):
            if '\x00' in target:
                continue
            resolved = (p.parent / target).resolve()
            if not is_markdown_file(resolved):
                continue
            if resolved in body_seen:
                continue
            body_seen.add(resolved)
            body_kids.append(resolved)
        backlinks_children_of[p] = body_kids

    backlinks_parents_of: dict[Path, list[Path]] = {p: [] for p in all_paths}
    for parent, kids in backlinks_children_of.items():
        for child in kids:
            if child in backlinks_parents_of:
                backlinks_parents_of[child].append(parent)

    changed = 0
    for p in all_paths:
        lines = lines_map[p]
        if p.name == 'index.md':
            new_lines = remove_section(remove_section(lines, 'back'), 'backlink')
        elif is_expand_generated_t_note(p, lines):
            new_lines = lines
        else:
            new_lines = lines
            up_link_targets = up_targets(new_lines, p)
            backlinks_parents = sorted(
                parent for parent in set(backlinks_parents_of.get(p, []))
                if parent not in up_link_targets
            )
            existing_back = section_content(new_lines, "backlink")
            new_back = build_back(backlinks_parents, p, existing_back)
            new_lines = replace_section(new_lines, "backlink", new_back)

        if new_lines != lines:
            write_lines(p, new_lines)
            changed += 1
    return changed


# ---------------------------------------------------------------------------
# update_one: update titles + up for a single file (fast, for autosync)
# ---------------------------------------------------------------------------

def update_one(file_path: Path, root: Path) -> str:
    """Update one file and rebuild backlink sections across the PKM root."""
    file_path = file_path.resolve()
    root = root.resolve()

    changed_files: list[str] = []

    if update_titles_in_file(file_path):
        changed_files.append(file_path.name)

    changed_count = update_up_sections(root)
    if changed_count:
        changed_files.append(f"uplinks:{changed_count}")

    if changed_files:
        return "yurii_PKM: updated " + ", ".join(changed_files)
    return "yurii_PKM: no changes"


# ---------------------------------------------------------------------------
# rename_prefix: ファイルのプレフィクスを変更し、全リンクを更新
# ---------------------------------------------------------------------------

def rename_prefix(old_path: Path, new_prefix: str, root: Path) -> str:
    """Rename old_path's prefix to new_prefix, update all Branch/Back links in root.

    Returns a human-readable summary string.
    """
    old_path = old_path.resolve()
    root = root.resolve()

    if not old_path.exists():
        raise FileNotFoundError(f"File not found: {old_path}")
    if not is_markdown_file(old_path):
        raise ValueError(f"Not a markdown file: {old_path}")

    old_name = old_path.name          # e.g. "S_250101120000.md"
    old_stem = old_path.stem          # e.g. "S_250101120000"

    # プレフィクス部分（最初の '_' より前）と残り部分に分割
    if '_' in old_stem:
        _, rest = old_stem.split('_', 1)
    else:
        rest = old_stem

    new_stem = f"{new_prefix}_{rest}"
    new_name = f"{new_stem}.md"
    new_path = old_path.parent / new_name

    if new_path.exists():
        raise FileExistsError(f"Target already exists: {new_path}")

    # 1. ファイル自体をリネーム
    old_path.rename(new_path)

    # 2. リネームしたファイル自身のBackセクション内に旧名リンクが残っていれば更新
    #    (expand_s.py が生成するAノートの末尾などを想定)
    self_lines = read_lines(new_path)
    self_lines = _rewrite_link_target(self_lines, old_name, new_name)
    write_lines(new_path, self_lines)

    # 3. PKMルート配下の全.mdファイルのBranch/Backリンクを更新
    changed: list[str] = []
    for p in iter_notes(root):
        if p.resolve() == new_path.resolve():
            continue
        lines = read_lines(p)
        new_lines = _rewrite_link_target(lines, old_name, new_name)
        if new_lines != lines:
            write_lines(p, new_lines)
            changed.append(p.name)

    summary_parts = [f"Renamed: {old_name} → {new_name}"]
    if changed:
        summary_parts.append(f"Updated links in: {', '.join(changed)}")
    else:
        summary_parts.append("No other files had links to update")
    return "\n".join(summary_parts)


def _rewrite_link_target(lines: list[str], old_name: str, new_name: str) -> list[str]:
    """Replace occurrences of old_name as a link target with new_name.

    Matches `](old_name)` patterns (exact filename, no path components).
    Also updates `[old_stem](...)` link text that equals the old stem.
    """
    old_stem = old_name[:-3] if old_name.endswith('.md') else old_name
    new_stem = new_name[:-3] if new_name.endswith('.md') else new_name

    # Matches [text](old_name) — the target filename must match exactly
    # (handles paths like `subdir/old_name` too by checking the basename)
    target_re = re.compile(
        r'(\[[^\]]*\]\()([^)]*?)(' + re.escape(old_name) + r')(\))',
    )
    # Also match bare old_stem as link text when target uses old_name
    text_re = re.compile(
        r'(\[)(' + re.escape(old_stem) + r')(\]\()([^)]*?)(' + re.escape(old_name) + r')(\))',
    )

    result = []
    for line in lines:
        # First pass: update link text if it equals old_stem
        new_line = text_re.sub(
            lambda m: m.group(1) + new_stem + m.group(3) + m.group(4) + new_name + m.group(6),
            line,
        )
        # Second pass: update any remaining target references
        new_line = target_re.sub(
            lambda m: m.group(1) + m.group(2) + new_name + m.group(4),
            new_line,
        )
        result.append(new_line)
    return result


def retitle_links(target_file: Path, root: Path, old_title: str, new_title: str) -> int:
    """Rename link text old_title -> new_title only for links targeting target_file."""
    target_resolved = target_file.resolve()
    changed_files = 0

    for p in iter_notes(root):
        lines = read_lines(p)
        modified = False
        out: list[str] = []

        for line in lines:
            m = re.match(r'^(\s*)\[([^\]]+)\]\(([^)]+)\)(\s*)$', line)
            if not m:
                out.append(line)
                continue
            text = m.group(2)
            rel_target = m.group(3)
            if text != old_title:
                out.append(line)
                continue
            resolved = (p.parent / rel_target).resolve()
            if resolved != target_resolved:
                out.append(line)
                continue
            modified = True
            out.append(f"{m.group(1)}[{new_title}]({rel_target}){m.group(4)}")

        if modified:
            write_lines(p, out)
            changed_files += 1

    return changed_files


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage:\n"
              "  yurii_pkm_sync.py update ROOT\n"
              "  yurii_pkm_sync.py update_one FILE ROOT\n"
              "  yurii_pkm_sync.py update_titles FILE\n"
              "  yurii_pkm_sync.py retitle_links FILE ROOT OLD_TITLE NEW_TITLE\n"
              "  yurii_pkm_sync.py rename_prefix FILE NEW_PREFIX ROOT",
              file=sys.stderr)
        return 2

    mode = argv[1]

    if mode == "update":
        root = Path(argv[2])
        if not root.exists():
            root.mkdir(parents=True, exist_ok=True)
        changed = update_up_sections(root)
        # Also update title annotations in all files
        title_changed = 0
        for p in iter_notes(root):
            if update_titles_in_file(p):
                title_changed += 1
        print(f"yurii_PKM: updated {changed + title_changed} file(s) under {root}")
        return 0

    if mode == "update_one":
        if len(argv) < 4:
            print("usage: yurii_pkm_sync.py update_one FILE ROOT", file=sys.stderr)
            return 2
        file_path = Path(argv[2])
        root = Path(argv[3])
        print(update_one(file_path, root))
        return 0

    if mode == "update_titles":
        path = Path(argv[2])
        changed = update_titles_in_file(path)
        print(f"yurii_PKM: {'updated' if changed else 'no changes in'} {path.name}")
        return 0

    if mode == "retitle_links":
        if len(argv) < 6:
            print("usage: yurii_pkm_sync.py retitle_links FILE ROOT OLD_TITLE NEW_TITLE",
                  file=sys.stderr)
            return 2
        target_file = Path(argv[2])
        root = Path(argv[3])
        old_title = argv[4]
        new_title = argv[5]
        changed = retitle_links(target_file, root, old_title, new_title)
        print(f"yurii_PKM: retitled {changed} file(s)")
        return 0

    if mode == "nf":
        if len(argv) < 4:
            print("usage: yurii_pkm_sync.py nf FILE ROOT", file=sys.stderr)
            return 2
        file_path = Path(argv[2])
        root = Path(argv[3])
        new_f = create_f_and_link(file_path, root)
        print(str(new_f))
        return 0

    if mode == "rename_prefix":
        if len(argv) < 5:
            print("usage: yurii_pkm_sync.py rename_prefix FILE NEW_PREFIX ROOT",
                  file=sys.stderr)
            return 2
        old_file   = Path(argv[2])
        new_prefix = argv[3]
        root       = Path(argv[4])
        try:
            result = rename_prefix(old_file, new_prefix, root)
            print(result)
            # 新ファイルパスを最終行に出力（Vim 側がパースする）
            old_stem = old_file.stem
            rest = old_stem.split("_", 1)[1] if "_" in old_stem else old_stem
            new_path = old_file.parent / f"{new_prefix}_{rest}.md"
            print(f"NEW_PATH:{new_path}")
        except (FileNotFoundError, FileExistsError, ValueError) as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        return 0

    print(f"unsupported mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
