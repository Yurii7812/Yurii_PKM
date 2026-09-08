#!/usr/bin/env python3
"""Yurii_PKM ノート形式 v2 の parse / render / sync。

詳細仕様は repo ルートの NOTE_FORMAT.md。要点:

- ファイル名 = タイムスタンプのみ。front matter は time / title。
- 本文の後、``<!-- している -->`` 見張り行から上側（このノートが「している」こと）。
- ``<!-- されている -->`` 見張り行から下側（「されている」こと）。
  HTML コメントなのでレンダラで不可視・見出し化しない・本文と衝突しない。
- 既知の関係: カテゴリー / 前提 / 論点 / 見解 / ワード / 関連。
  それ以外の ``語:`` 見出しも関係として扱う（自由入力）。
- リンク 1 本は ``関係: [t](x.md)`` のインライン、2 本以上は ``関係:`` 改行のブロック。
- 上側が真実。下側は他ノートの上側から導出。上下どちらも編集でき、
  片面の追加 / 削除はもう片面へ反映される（``.pkm_sync_state_v2.json`` で判定）。
- 本文（散文）中のリンクは、明示の関係が無ければ相手の下側に
  ``バックリンク:`` として現れる。

CLI:
    note_format_v2.py update      ROOT
    note_format_v2.py update_one  FILE ROOT
    note_format_v2.py new         FILE ROOT [TITLE]
"""
from __future__ import annotations

import datetime as _dt
import json
import os
import re
import sys
from pathlib import Path

RELATIONS: tuple[str, ...] = ("カテゴリー", "前提", "論点", "見解", "ワード", "関連")
BACKLINK = "バックリンク"

UP_MARK = "<!-- している -->"
DOWN_MARK = "<!-- されている -->"

DIVIDER_RE = re.compile(r"^-{3,}\s*$")
# 任意の `語:` 見出し（先頭が空白 / # / : でない）。散文除けは _looks_like_header で行う。
HEADER_RE = re.compile(r"^([^\s:#][^:]*?)\s*:\s*(.*)$")
# [表示]() 形式のリンク行（末尾に「 — 注釈」を許す）
LINK_LINE_RE = re.compile(r"^\s*\[([^\]]*)\]\(([^)]+)\)\s*(?:—\s*(.*\S))?\s*$")
# 本文どこにでも現れるリンク（バックリンク判定用）
ANY_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
# 旧 v1 の構造見出し
LEGACY_HDR_RE = re.compile(r"^(Parent|Child|Branch|BackLink|Back)\s*:\s*(.*)$", re.I)

_EXTRA = "_extra"
_RESERVED = {_EXTRA, BACKLINK}


class Note:
    __slots__ = ("path", "fm", "title", "body", "up", "down", "managed")

    def __init__(self, path, fm, title, body, up, down, managed=True):
        self.path: Path = Path(path)
        self.fm: list[str] = fm
        self.title: str = title
        self.body: list[str] = body
        # managed=False: PKM 形式でない外部ファイル（日記など）。sync は書き換えない。
        self.managed: bool = managed
        self.up: dict[str, list[tuple[str, str, str | None]]] = up
        self.down: dict[str, list[tuple[str, str, str | None]]] = down


# ---------------------------------------------------------------------------
# parse
# ---------------------------------------------------------------------------

def _split_front_matter(lines: list[str]) -> tuple[list[str], list[str]]:
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return lines[: i + 1], lines[i + 1:]
    return [], list(lines)


def _fm_title(fm: list[str]) -> str:
    for ln in fm:
        m = re.match(r"^\s*title\s*:\s*(.+?)\s*$", ln)
        if m:
            return m.group(1)
    return ""


def _looks_like_header(m: re.Match, lines: list[str], idx: int) -> bool:
    inline = m.group(2).strip()
    if inline:
        return bool(LINK_LINE_RE.match(inline))
    for j in range(idx + 1, min(idx + 4, len(lines))):
        s = lines[j].strip()
        if s == "":
            continue
        return bool(LINK_LINE_RE.match(s))
    return False


def _parse_sections(lines: list[str], allow_body: bool):
    body: list[str] = []
    sections: dict[str, list] = {}
    cur: str | None = None
    seen_header = False
    i, n = 0, len(lines)
    while i < n:
        ln = lines[i]
        s = ln.strip()
        m = HEADER_RE.match(s)
        if m and _looks_like_header(m, lines, i):
            cur = m.group(1).strip()
            seen_header = True
            sections.setdefault(cur, [])
            lm = LINK_LINE_RE.match(m.group(2).strip())
            if lm:
                sections[cur].append((lm.group(1), lm.group(2), lm.group(3) or None))
            i += 1
            continue
        lm = LINK_LINE_RE.match(s)
        if lm and cur is not None:
            sections[cur].append((lm.group(1), lm.group(2), lm.group(3) or None))
            i += 1
            continue
        cur = None
        if s == "":
            if allow_body and not seen_header:
                body.append(ln)
        elif allow_body and not seen_header:
            body.append(ln)
        else:
            sections.setdefault(_EXTRA, []).append(ln)
        i += 1
    while body and body[-1].strip() == "":
        body.pop()
    return body, sections


def _has_relation_header(lines: list[str]) -> bool:
    for j, l in enumerate(lines):
        m = HEADER_RE.match(l.strip())
        if m and _looks_like_header(m, lines, j):
            return True
    return False


def _route_legacy_link(up: dict, ti: str, tg: str, ann: str | None) -> None:
    base = tg.split("#", 1)[0].rsplit("/", 1)[-1].lower()
    kind = "カテゴリー" if base in ("index.md", "index") else "関連"
    up.setdefault(kind, [])
    if all(e[1] != tg for e in up[kind]):
        up[kind].append((ti, tg, ann))


def _migrate_legacy(lines: list[str]):
    """旧 v1（Parent:/Child:/BackLink:）を v2 の形へ寄せる。

    Parent/Child/Branch のリンク -> ``関連:``、``[Index](index.md)`` -> ``カテゴリー:``。
    BackLink は捨てる（sync が下側に再生成する）。リンクは失わない。
    """
    body: list[str] = []
    up: dict[str, list] = {}
    down: dict[str, list] = {}
    zone: object = None  # None | "up" | "back" | ("rel", 関係)
    seen = False
    for idx, ln in enumerate(lines):
        s = ln.strip()
        lm = LINK_LINE_RE.match(s)
        if lm and lm.group(2).split("#", 1)[0].rsplit("/", 1)[-1].lower() in ("index.md", "index"):
            _route_legacy_link(up, lm.group(1), lm.group(2), lm.group(3) or None)
            continue
        lg = LEGACY_HDR_RE.match(s)
        if lg:
            seen = True
            name = lg.group(1).lower()
            zone = "back" if name in ("backlink", "back") else "up"
            inln = LINK_LINE_RE.match(lg.group(2).strip())
            if inln and zone == "up":
                _route_legacy_link(up, inln.group(1), inln.group(2), inln.group(3) or None)
            continue
        tm = HEADER_RE.match(s)
        if tm and _looks_like_header(tm, lines, idx):
            seen = True
            zone = ("rel", tm.group(1).strip())
            up.setdefault(zone[1], [])
            inln = LINK_LINE_RE.match(tm.group(2).strip())
            if inln:
                up[zone[1]].append((inln.group(1), inln.group(2), inln.group(3) or None))
            continue
        if lm:
            if zone == "up":
                _route_legacy_link(up, lm.group(1), lm.group(2), lm.group(3) or None)
            elif isinstance(zone, tuple):
                up[zone[1]].append((lm.group(1), lm.group(2), lm.group(3) or None))
            continue
        if not seen:
            body.append(ln)
    while body and body[-1].strip() == "":
        body.pop()
    return body, up, down


def parse_note(path, text: str | None = None) -> Note:
    p = Path(path)
    if text is None:
        text = p.read_text(encoding="utf-8")
    raw = text.split("\n")
    fm, rest = _split_front_matter(raw)
    title = _fm_title(fm) or p.stem

    stripped = [ln.strip() for ln in rest]

    # front matter で明示的に除外（pkm: raw / sync: false）
    if re.search(r"^\s*(pkm\s*:\s*raw|sync\s*:\s*(?:false|off|no))\s*$", "\n".join(fm), re.I | re.M):
        body = list(rest)
        while body and body[-1].strip() == "":
            body.pop()
        return Note(p, fm, title, body, {}, {}, managed=False)

    # 見張り行: HTML コメント。レンダラで不可視・見出し化しない・本文と衝突しない。
    if UP_MARK in stripped and DOWN_MARK in stripped:
        u = len(stripped) - 1 - stripped[::-1].index(UP_MARK)
        d = len(stripped) - 1 - stripped[::-1].index(DOWN_MARK)
        if u > d:
            u = stripped.index(UP_MARK)
        body_lines = rest[:u]
        up_lines = rest[u + 1: d]
        down_lines: list[str] = rest[d + 1:]
    else:
        # --- 旧形式からの移行。関係らしい中身がある時だけ構造扱いする ---
        div_idx = [i for i, s in enumerate(stripped) if DIVIDER_RE.match(s)]
        if len(div_idx) >= 2 and (
            _has_relation_header(rest[div_idx[-2] + 1:])
            or all(x == "" for x in stripped[div_idx[-2] + 1:])
        ):  # 旧 v2: `---` 2 本
            body_lines = rest[:div_idx[-2]]
            up_lines = rest[div_idx[-2] + 1: div_idx[-1]]
            down_lines = rest[div_idx[-1] + 1:]
        elif len(div_idx) == 1 and (
            _has_relation_header(rest[div_idx[0] + 1:])
            or all(x == "" for x in stripped[div_idx[0] + 1:])
        ):  # 旧 v2: 単一 `---`
            body_lines = rest[:div_idx[0]]
            up_lines = rest[div_idx[0] + 1:]
            down_lines = []
        elif any(LEGACY_HDR_RE.match(s) for s in stripped):  # v1
            body, up, down = _migrate_legacy(rest)
            return Note(p, fm, title, body, up, down)
        else:
            # PKM 形式でない外部ファイル（日記など）。読むだけ、書き換えない。
            body = list(rest)
            while body and body[-1].strip() == "":
                body.pop()
            return Note(p, fm, title, body, {}, {}, managed=False)

    body = list(body_lines)
    while body and body[-1].strip() == "":
        body.pop()
    _, up = _parse_sections(up_lines, allow_body=False)
    _, down = _parse_sections(down_lines, allow_body=False)
    return Note(p, fm, title, body, up, down)


def _links_in(lines: list[str]) -> list[str]:
    out: list[str] = []
    for ln in lines:
        for m in ANY_LINK_RE.finditer(ln):
            t = m.group(1).split("#", 1)[0].strip()
            if t.lower().endswith(".md"):
                out.append(t)
    return out


# ---------------------------------------------------------------------------
# render
# ---------------------------------------------------------------------------

def _render_section(t: str, entries: list[tuple[str, str, str | None]]) -> list[str]:
    if not entries:
        return []
    if len(entries) == 1:
        ti, tg, ann = entries[0]
        s = f"{t}: [{ti}]({tg})"
        return [s + f" — {ann}" if ann else s]
    out = [f"{t}:"]
    for ti, tg, ann in entries:
        s = f"[{ti}]({tg})"
        out.append(s + f" — {ann}" if ann else s)
    return out


def _render_group(d: dict[str, list], is_down: bool = False) -> list[str]:
    out: list[str] = []
    done: set[str] = set()
    for t in RELATIONS:
        if d.get(t):
            out += _render_section(t, d[t])
            done.add(t)
    for t in d:
        if t in _RESERVED or t in done:
            continue
        if d.get(t):
            out += _render_section(t, d[t])
            done.add(t)
    if is_down and d.get(BACKLINK):
        out += _render_section(BACKLINK, d[BACKLINK])
    out += list(d.get(_EXTRA, []))
    return out


def _squeeze_blanks(lines: list[str]) -> list[str]:
    res: list[str] = []
    prev_blank = False
    for ln in lines:
        blank = ln.strip() == ""
        if blank and prev_blank:
            continue
        res.append(ln)
        prev_blank = blank
    return res


def render_note(note: Note) -> str:
    out: list[str] = list(note.fm)
    out.append("")
    out += note.body

    # 本文 → (空行) している見張り → 上側 → されている見張り → 下側
    out.append("")
    out.append(UP_MARK)
    out += _render_group(note.up)
    out.append(DOWN_MARK)
    out += _render_group(note.down, is_down=True)

    out = _squeeze_blanks(out)
    while out and out[-1].strip() == "":
        out.pop()
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# resolution helpers
# ---------------------------------------------------------------------------

def _iter_md(root: Path):
    for p in sorted(root.rglob("*.md")):
        if any(part.startswith(".") for part in p.relative_to(root).parts):
            continue
        yield p


def _index(root: Path) -> dict[str, list[Path]]:
    by_name: dict[str, list[Path]] = {}
    for p in _iter_md(root):
        rp = p.resolve()
        by_name.setdefault(p.name, []).append(rp)
        by_name.setdefault(p.stem, []).append(rp)
    return by_name


def _resolve(target: str, note_dir: Path, root: Path, by_name: dict[str, list[Path]]) -> Path | None:
    t = target.split("#", 1)[0].strip()
    if not t or "://" in t:
        return None
    cand = note_dir / t
    try:
        cand = cand.resolve()
    except OSError:
        cand = None
    if cand is not None and cand.suffix.lower() == ".md" and cand.exists():
        return cand
    key = Path(t).name
    lst = by_name.get(key) or by_name.get(key[:-3] if key.endswith(".md") else key)
    if lst:
        uniq = set(lst)
        if len(uniq) == 1:
            return next(iter(uniq))
    return None


def _rel(from_dir: Path, target: Path) -> str:
    return os.path.relpath(target, from_dir).replace(os.sep, "/")


# ---------------------------------------------------------------------------
# sync
# ---------------------------------------------------------------------------

_STATE_FILE = ".pkm_sync_state_v2.json"
Rel = tuple[str, str, str]  # (src_id, type, tgt_id)  id = root からの相対 posix パス


def _nid(path: Path, root: Path) -> str | None:
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return None


def _load_state(root: Path) -> set[Rel]:
    fp = root / _STATE_FILE
    if not fp.exists():
        return set()
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        return {tuple(x.split("\t")) for x in data if isinstance(x, str) and x.count("\t") == 2}
    except Exception:  # noqa: BLE001
        return set()


def _save_state(root: Path, present: set[Rel]) -> None:
    fp = root / _STATE_FILE
    payload = sorted("\t".join(r) for r in present)
    fp.write_text(json.dumps(payload, ensure_ascii=False, indent=0), encoding="utf-8")


def sync_vault(root) -> int:
    """vault 全体を 1 パスで整合させる。"""
    root = Path(root).resolve()
    by_name = _index(root)

    notes: list[Note] = []
    for p in _iter_md(root):
        try:
            notes.append(parse_note(p))
        except Exception as exc:  # noqa: BLE001
            print(f"note_format_v2: skip {p}: {exc}", file=sys.stderr)

    by_path: dict[Path, Note] = {n.path.resolve(): n for n in notes}
    ids: dict[Path, str] = {}
    id_to_path: dict[str, Path] = {}
    for k in by_path:
        i = _nid(k, root)
        if i is not None:
            ids[k] = i
            id_to_path[i] = k

    def rid(target: str, base: Path) -> str | None:
        tp = _resolve(target, base, root, by_name)
        return ids.get(tp.resolve()) if tp is not None else None

    observed_up: set[Rel] = set()
    observed_down: set[Rel] = set()
    up_ann: dict[Rel, str] = {}
    up_unresolved: dict[Path, dict[str, list]] = {k: {} for k in by_path}
    body_links: dict[str, set[str]] = {}

    for k, n in by_path.items():
        sid = ids.get(k)
        if sid is None:
            continue
        for t, entries in n.up.items():
            if t == _EXTRA:
                continue
            for ti, tg, ann in entries:
                tid = rid(tg, n.path.parent)
                if tid is None:
                    up_unresolved[k].setdefault(t, []).append((ti, tg, ann))
                    continue
                r = (sid, t, tid)
                observed_up.add(r)
                if ann:
                    up_ann[r] = ann
        for t, entries in n.down.items():
            if t in _RESERVED:
                continue
            for _ti, tg, _ann in entries:
                src_id = rid(tg, n.path.parent)
                if src_id is not None:
                    observed_down.add((src_id, t, sid))
        bl: set[str] = set()
        for tg in _links_in(n.body):
            tid = rid(tg, n.path.parent)
            if tid is not None and tid != sid:
                bl.add(tid)
        body_links[sid] = bl

    prev = _load_state(root)
    present: set[Rel] = set()
    for r in observed_up | observed_down | prev:
        up_face = r in observed_up
        down_face = r in observed_down
        if up_face and down_face:
            present.add(r)
        elif up_face != down_face and r not in prev:
            present.add(r)  # 片面だけ & 前回に無い = 今追加した
    present = {r for r in present if r[0] in id_to_path and r[2] in id_to_path}

    directed = {(s, tt) for (s, _ty, tt) in present}  # 関係を問わない src->tgt

    # --- 上側を present から再構築 ---
    for k, n in by_path.items():
        sid = ids.get(k)
        if sid is None:
            continue
        types_here = set(RELATIONS) | set(n.up) | {ty for (s, ty, _t) in present if s == sid}
        types_here.discard(_EXTRA)
        new_up: dict[str, list] = {}
        for t in types_here:
            order = [rid(tg, n.path.parent) for _ti, tg, _a in n.up.get(t, [])]
            wanted = [tid for tid in order if tid and (sid, t, tid) in present]
            for (s2, t2, tgt2) in present:
                if s2 == sid and t2 == t and tgt2 not in wanted:
                    wanted.append(tgt2)
            entries = []
            for tid in wanted:
                tp = id_to_path[tid]
                entries.append((by_path[tp].title, _rel(n.path.parent, tp), up_ann.get((sid, t, tid))))
            entries += up_unresolved[k].get(t, [])
            if entries:
                new_up[t] = entries
        if n.up.get(_EXTRA):
            new_up[_EXTRA] = n.up[_EXTRA]
        n.up = new_up

    # --- 下側を再構築（関係 + バックリンク） ---
    for k, n in by_path.items():
        nid = ids.get(k)
        new_down: dict[str, list] = {}
        if nid is not None:
            by_type: dict[str, list[str]] = {}
            for (s, t, tg) in present:
                if tg == nid and (nid, t, s) not in present:  # 相互リンクは出さない
                    by_type.setdefault(t, []).append(s)
            for t, srcs in by_type.items():
                new_down[t] = [
                    (by_path[id_to_path[s]].title, _rel(n.path.parent, id_to_path[s]), None)
                    for s in sorted(set(srcs))
                ]
            back = sorted(
                s for s, targets in body_links.items()
                if nid in targets and (s, nid) not in directed and s in id_to_path
            )
            if back:
                new_down[BACKLINK] = [
                    (by_path[id_to_path[s]].title, _rel(n.path.parent, id_to_path[s]), None)
                    for s in back
                ]
        if n.down.get(_EXTRA):
            new_down[_EXTRA] = n.down[_EXTRA]
        n.down = new_down

    _save_state(root, present)

    changed = 0
    for n in notes:
        if not n.managed:  # 外部ファイル（日記など）は絶対に書き換えない
            continue
        new_text = render_note(n)
        if new_text != n.path.read_text(encoding="utf-8"):
            n.path.write_text(new_text, encoding="utf-8")
            changed += 1
    return changed


def update_one(file_path, root) -> str:
    changed = sync_vault(root)
    return f"yurii_PKM: v2 synced {changed} file(s)" if changed else "yurii_PKM: no changes"


# ---------------------------------------------------------------------------
# new note
# ---------------------------------------------------------------------------

def make_new(path, title: str = "") -> Path:
    p = Path(path)
    ts = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    t = title.strip() or p.stem
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(
        f"---\ntime: {ts}\ntitle: {t}\n---\n\n# {t}\n\n\n{UP_MARK}\n{DOWN_MARK}\n",
        encoding="utf-8",
    )
    return p


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    mode = argv[1]
    if mode == "update":
        changed = sync_vault(argv[2])
        print(f"yurii_PKM: v2 updated {changed} file(s) under {argv[2]}")
        return 0
    if mode == "update_one":
        if len(argv) < 4:
            print("usage: note_format_v2.py update_one FILE ROOT", file=sys.stderr)
            return 2
        print(update_one(argv[2], argv[3]))
        return 0
    if mode == "new":
        if len(argv) < 4:
            print("usage: note_format_v2.py new FILE ROOT [TITLE]", file=sys.stderr)
            return 2
        title = argv[4] if len(argv) > 4 else ""
        p = make_new(argv[2], title)
        sync_vault(argv[3])
        print(str(p))
        return 0
    if mode == "retitle_links":
        if len(argv) >= 4:
            sync_vault(argv[3])
        print("yurii_PKM: v2 retitle via sync")
        return 0
    if mode in {"update_titles", "rename_prefix", "reparent_down_children", "nf"}:
        print(f"yurii_PKM: v2 ignores mode '{mode}'", file=sys.stderr)
        return 0
    print(f"unsupported mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
