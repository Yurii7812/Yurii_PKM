#!/usr/bin/env python3
"""expand_s.py  -- 任意ノート内の本文リンクを展開して T ノートを作る

usage:
    expand_s.py expand_s FILE ROOT [DEPTH]
    expand_s.py expand_any FILE ROOT [DEPTH]

- FILE の本文にある markdown リンクを展開する
- Back セクション以降は読まない
- 生成先は ROOT/T_YYMMDDhhmmss.md
- DEPTH は再帰展開の深さ
    0: 展開しない（空ファイルになりうる）
    1: 直接リンクのみ
    2: 1段深く再帰
    ...
"""
from __future__ import annotations

import re
import sys
from datetime import datetime
from pathlib import Path

LINK_RE = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
TITLE_RE = re.compile(r'^title:\s*(.*)$', re.IGNORECASE)
H1_RE = re.compile(r'^#{1,6}\s+(.+)$')


def bare_section_name(text: str) -> str:
    stripped = text.strip()
    stripped = re.sub(r'^#+\s*', '', stripped)
    return stripped.lower()


def is_section_header(text: str, name: str) -> bool:
    return bare_section_name(text) == name.lower()


def is_markdown_file(path: Path) -> bool:
    return path.suffix.lower() == '.md'


def read_lines(path: Path) -> list[str]:
    if not is_markdown_file(path):
        return []
    return path.read_text(encoding='utf-8').splitlines()


def write_lines(path: Path, lines: list[str]) -> None:
    text = '\n'.join(lines)
    if not text.endswith('\n'):
        text += '\n'
    path.write_text(text, encoding='utf-8')


def timestamp_filename() -> str:
    return datetime.now().strftime('%y%m%d%H%M%S')


def split_note(path: Path) -> tuple[str, list[str]]:
    """ノートを (title, body_lines) に分解する。

    対応順:
    1. YAML title
    2. 先頭付近の H1
    3. 本文最初の非空行をタイトル扱い

    Back セクション以降は本文に含めない。
    Branch 見出し単独行は無視する。
    """
    lines = read_lines(path)
    i = 0
    yaml_title = ''

    if lines and lines[0].strip() == '---':
        i = 1
        while i < len(lines):
            stripped = lines[i].strip()
            if stripped == '---':
                i += 1
                break
            m = TITLE_RE.match(lines[i])
            if m:
                yaml_title = m.group(1).strip().strip('"\'')
            i += 1

    while i < len(lines) and lines[i].strip() == '':
        i += 1

    title = yaml_title.strip()
    if i < len(lines):
        h1 = H1_RE.match(lines[i].strip())
        if h1:
            if not title:
                title = h1.group(1).strip()
            i += 1
            while i < len(lines) and lines[i].strip() == '':
                i += 1
        elif not title and lines[i].strip() and not is_section_header(lines[i].strip(), 'back'):
            # リンクのみ行はタイトルとして取り込まない（本文として展開させる）
            candidate = lines[i].strip()
            if not LINK_RE.match(candidate):
                title = candidate
                i += 1
                while i < len(lines) and lines[i].strip() == '':
                    i += 1

    if not title:
        title = path.stem

    body: list[str] = []
    in_fence = False
    for line in lines[i:]:
        stripped = line.strip()
        if stripped.startswith('```'):
            in_fence = not in_fence
            body.append(line)
            continue
        if not in_fence and is_section_header(stripped, 'back'):
            break
        if not in_fence and is_section_header(stripped, 'branch'):
            continue
        body.append(line)

    while body and body[0].strip() == '':
        body.pop(0)
    while body and body[-1].strip() == '':
        body.pop()
    return title, body


def extract_body_until_back(path: Path) -> list[str]:
    return split_note(path)[1]


def note_title(lines: list[str], path: Path) -> str:
    del lines
    return split_note(path)[0]


def body_links(path: Path) -> list[tuple[str, Path]]:
    """本文（Back 以前）にあるリンクを順番通り返す。重複は 1 回。"""
    body = extract_body_until_back(path)
    seen: set[Path] = set()
    result: list[tuple[str, Path]] = []
    in_fence = False
    for line in body:
        stripped = line.strip()
        if stripped.startswith('```'):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for text, target in LINK_RE.findall(line):
            if '\x00' in target:
                continue
            target_path = (path.parent / target).resolve()
            if not is_markdown_file(target_path):
                continue
            if not target_path.exists():
                continue
            if target_path in seen:
                continue
            seen.add(target_path)
            result.append((text, target_path))
    return result


def heading_for_depth(depth: int, title: str) -> str:
    level = max(2, min(depth, 6))
    return ('#' * level) + ' ' + title


def expand_body_inline(body: list[str], source_path: Path, heading_depth: int,
                       expand_depth: int, active_stack: set[Path]) -> list[str]:
    """本文を行ごとに走査し、リンク行をその場でインライン展開して返す。

    - リンクを含む行: リンク先を見出し＋本文に置き換える（行内の他テキストは捨てる）
    - リンクを含まない行: そのまま出力
    - コードフェンス内はリンク展開しない
    """
    out: list[str] = []
    in_fence = False
    seen: set[Path] = set()

    for line in body:
        stripped = line.strip()

        # コードフェンスの開閉を追跡
        if stripped.startswith('```'):
            in_fence = not in_fence
            out.append(line)
            continue

        if in_fence:
            out.append(line)
            continue

        # 行内のリンクを探す（text と path のペアで収集）
        links_in_line: list[tuple[str, Path]] = []
        for text, target in LINK_RE.findall(line):
            if '\x00' in target:
                continue
            target_path = (source_path.parent / target).resolve()
            if not is_markdown_file(target_path):
                continue
            if not target_path.exists():
                continue
            if target_path in seen:
                continue
            links_in_line.append((text.strip(), target_path))

        if not links_in_line:
            # リンクなし行: そのまま出力
            out.append(line)
            continue

        # リンクあり行: 行内の全リンクをその場で展開
        for link_text, target_path in links_in_line:
            seen.add(target_path)
            resolved = target_path.resolve()

            if resolved in active_stack:
                out.append(heading_for_depth(heading_depth, resolved.stem))
                out.append('')
                out.append('_(recursive cycle skipped)_')
                out.append('')
                out.append('##')
                out.append('')
                continue

            title, nested_body = split_note(resolved)
            out.append(heading_for_depth(heading_depth, title))
            out.append('')

            if expand_depth > 0 and nested_body:
                if expand_depth == 1:
                    out.extend(nested_body)
                else:
                    next_stack = set(active_stack)
                    next_stack.add(resolved)
                    expanded = expand_body_inline(
                        nested_body,
                        resolved,
                        min(heading_depth + 1, 6),
                        expand_depth - 1,
                        next_stack,
                    )
                    out.extend(expanded)

            # 展開内容後、空行を確保して ## 区切り
            if out and out[-1].strip() != '':
                out.append('')
            out.append('##')
            out.append('')

    return out


def build_expanded_content(source_path: Path, depth: int) -> list[str]:
    """ソースファイルの本文をインライン展開して返す。

    depth == 0 のときはソース本文をそのまま出力（展開なし）。
    """
    title, body = split_note(source_path)

    if depth <= 0:
        content = list(body)
    else:
        content = expand_body_inline(
            body,
            source_path,
            heading_depth=2,
            expand_depth=depth,
            active_stack={source_path.resolve()},
        )

    header = ['# ' + title, '']
    content = header + content

    while content and content[-1].strip() == '':
        content.pop()
    content.append('')
    return content


def expand_note(file_path: Path, root: Path, depth: int) -> Path:
    ts = timestamp_filename()
    t_path = root / f'T_{ts}.md'
    root.mkdir(parents=True, exist_ok=True)
    write_lines(t_path, build_expanded_content(file_path, depth))
    return t_path


def parse_depth(arg: str | None) -> int:
    if arg is None:
        return 1
    try:
        depth = int(arg)
    except ValueError:
        raise SystemExit('Error: DEPTH must be an integer')
    if depth < 0:
        raise SystemExit('Error: DEPTH must be >= 0')
    return depth


def main(argv: list[str]) -> int:
    if len(argv) < 4 or argv[1] not in {'expand_s', 'expand_any'}:
        print('usage: expand_s.py expand_s FILE ROOT [DEPTH]', file=sys.stderr)
        print('   or: expand_s.py expand_any FILE ROOT [DEPTH]', file=sys.stderr)
        return 2

    file_path = Path(argv[2])
    root = Path(argv[3])
    depth = parse_depth(argv[4] if len(argv) >= 5 else None)

    if not file_path.exists():
        print(f'Error: file not found: {file_path}', file=sys.stderr)
        return 1
    if not is_markdown_file(file_path):
        print(f'Error: not a markdown file: {file_path}', file=sys.stderr)
        return 1

    t_path = expand_note(file_path, root, depth)
    print(str(t_path))
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
