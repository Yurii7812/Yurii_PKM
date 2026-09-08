#!/usr/bin/env python3
"""Yurii_PKM ノート形式 v2 の parse / render / sync。

詳細仕様は repo ルートの NOTE_FORMAT.md。要点:

- ファイル名 = タイムスタンプのみ。front matter は time / title。
- 本文の後に型付きセクション（上側 = このノートが「している」こと）。
- 単独行 ``---`` が上下の境界。その後ろが下側（「されている」こと）。
- 型: カテゴリー / 前提 / 論点 / ワード / 関連
- リンク 1 本は ``型: [t](x.md)`` のインライン、2 本以上は ``型:`` 改行のブロック。
- 上側が真実。下側は他ノートの上側から導出する。
  ただし下側も手で編集でき、下側への追加 / 削除は相方ノートの上側へ反映される。
- ``BackLink`` に相当する本文リンク走査は行わない（型付きリンクのみ）。

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

TYPES: tuple[str, ...] = ("カテゴリー", "前提", "論点", "ワード", "関連")

DIVIDER_RE = re.compile(r"^-{3,}\s*$")
HEADER_RE = re.compile(r"^(" + "|".join(map(re.escape, TYPES)) + r")\s*:\s*(.*)$")
# [表示]() 形式のリンク行（末尾に「 — 注釈」を許す）
LINK_LINE_RE = re.compile(r"^\s*\[([^\]]*)\]\(([^)]+)\)\s*(?:—\s*(.*\S))?\s*$")
# 旧 v1 の構造見出し
LEGACY_HDR_RE = re.compile(r"^(Parent|Child|Branch|BackLink|Back)\s*:\s*(.*)$", re.I)

_EXTRA = "_extra"


class Note:
    __slots__ = ("path", "fm", "title", "body", "up", "down")

    def __init__(self, path, fm, title, body, up, down):
        self.path: Path = Path(path)
        self.fm: list[str] = fm
        self.title: str = title
        self.body: list[str] = body
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
    sections: dict[str, list] = {t: [] for t in TYPES}
    cur: str | None = None
    seen_header = False
    i, n = 0, len(lines)
    while i < n:
        ln = lines[i]
        s = ln.strip()
        m = HEADER_RE.match(s)
        if m and _looks_like_header(m, lines, i):
            cur = m.group(1)
            seen_header = True
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
        # blank / stray
        cur = None
        if s == "":
            if allow_body and not seen_header:
                body.append(ln)
        else:
            if allow_body and not seen_header:
                body.append(ln)
            else:
                sections.setdefault(_EXTRA, []).append(ln)
        i += 1
    while body and body[-1].strip() == "":
        body.pop()
    return body, sections


def _route_legacy_link(up: dict, ti: str, tg: str, ann: str | None) -> None:
    base = tg.split("#", 1)[0].rsplit("/", 1)[-1].lower()
    kind = "カテゴリー" if base in ("index.md", "index") else "関連"
    if all(e[1] != tg for e in up[kind]):
        up[kind].append((ti, tg, ann))


def _migrate_legacy(lines: list[str]):
    """旧 v1（Parent:/Child:/BackLink:）を v2 の形へ寄せる。

    Parent/Child/Branch のリンク -> `関連:`、`[Index](index.md)` -> `カテゴリー:`。
    BackLink は捨てる（sync が下側に再生成する）。リンクは失わない。
    """
    body: list[str] = []
    up: dict[str, list] = {t: [] for t in TYPES}
    down: dict[str, list] = {t: [] for t in TYPES}
    zone: object = None  # None | "up" | "back" | ("typed", 型)
    seen = False
    for ln in lines:
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
        if tm:
            seen = True
            zone = ("typed", tm.group(1))
            inln = LINK_LINE_RE.match(tm.group(2).strip())
            if inln:
                up[tm.group(1)].append((inln.group(1), inln.group(2), inln.group(3) or None))
            continue
        if lm:
            if zone == "up":
                _route_legacy_link(up, lm.group(1), lm.group(2), lm.group(3) or None)
            elif isinstance(zone, tuple):
                up[zone[1]].append((lm.group(1), lm.group(2), lm.group(3) or None))
            # zone == "back" -> drop
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

    div = -1
    for i, ln in enumerate(rest):
        if DIVIDER_RE.match(ln.strip()):
            div = i
            break

    if div < 0 and any(LEGACY_HDR_RE.match(l.strip()) for l in rest):
        body, up, down = _migrate_legacy(rest)
        return Note(p, fm, title, body, up, down)

    up_lines = rest if div < 0 else rest[:div]
    down_lines: list[str] = [] if div < 0 else rest[div + 1:]

    body, up = _parse_sections(up_lines, allow_body=True)
    _, down = _parse_sections(down_lines, allow_body=False)
    return Note(p, fm, title, body, up, down)


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


def _render_group(d: dict[str, list]) -> list[str]:
    out: list[str] = []
    for t in TYPES:
        out += _render_section(t, d.get(t, []))
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

    up = _render_group(note.up)
    if up:
        out.append("")
        out += up

    out.append("")
    out.append("---")
    out += _render_group(note.down)

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
    """vault 全体を 1 パスで整合させる。

    有向関係 r=(src, type, tgt) は「src の上側」と「tgt の下側」の両方に現れるのが
    整合状態。前回整合時の集合を ``.pkm_sync_state_v2.json`` に持ち、上側だけ /
    下側だけに現れる関係を「追加」か「削除」か判定する。
    """
    root = Path(root).resolve()
    by_name = _index(root)

    notes: list[Note] = []
    for p in _iter_md(root):
        try:
            notes.append(parse_note(p))
        except Exception as exc:  # noqa: BLE001 - skip unparseable, keep going
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
        if tp is None:
            return None
        return ids.get(tp.resolve())

    observed_up: set[Rel] = set()
    observed_down: set[Rel] = set()
    up_ann: dict[Rel, str] = {}
    up_unresolved: dict[Path, dict[str, list]] = {k: {t: [] for t in TYPES} for k in by_path}

    for k, n in by_path.items():
        sid = ids.get(k)
        if sid is None:
            continue
        for t in TYPES:
            for ti, tg, ann in n.up.get(t, []):
                tid = rid(tg, n.path.parent)
                if tid is None:
                    up_unresolved[k][t].append((ti, tg, ann))
                    continue
                r = (sid, t, tid)
                observed_up.add(r)
                if ann:
                    up_ann[r] = ann
        for t in TYPES:
            for _ti, tg, _ann in n.down.get(t, []):
                src_id = rid(tg, n.path.parent)
                if src_id is not None:
                    observed_down.add((src_id, t, sid))

    prev = _load_state(root)
    present: set[Rel] = set()
    for r in observed_up | observed_down | prev:
        up_face = r in observed_up
        down_face = r in observed_down
        if up_face and down_face:
            present.add(r)
        elif up_face != down_face and r not in prev:
            present.add(r)  # 片面だけ & 前回に無い = ユーザが今追加した
        # 片面だけ & 前回にあった = ユーザが片面を削除した -> 関係ごと消す
    present = {r for r in present if r[0] in id_to_path and r[2] in id_to_path}

    # --- 上側を present から再構築（順序・注釈は既存を尊重、未解決は温存） ---
    for k, n in by_path.items():
        sid = ids.get(k)
        if sid is None:
            continue
        for t in TYPES:
            order: list[str] = []
            for _ti, tg, _ann in n.up.get(t, []):
                tid = rid(tg, n.path.parent)
                if tid is not None:
                    order.append(tid)
            wanted = [tid for tid in order if (sid, t, tid) in present]
            for (s2, t2, tgt2) in present:
                if s2 == sid and t2 == t and tgt2 not in wanted:
                    wanted.append(tgt2)
            entries = []
            for tid in wanted:
                tp = id_to_path[tid]
                entries.append((by_path[tp].title, _rel(n.path.parent, tp), up_ann.get((sid, t, tid))))
            entries += up_unresolved[k][t]
            if entries:
                n.up[t] = entries
            else:
                n.up.pop(t, None)

    # --- 下側を present から再構築（相互リンクは除外） ---
    for k, n in by_path.items():
        nid = ids.get(k)
        extra = n.down.get(_EXTRA)
        new_down: dict[str, list] = {t: [] for t in TYPES}
        if nid is not None:
            for t in TYPES:
                srcs = sorted(s for (s, tt, tg) in present if tt == t and tg == nid)
                for s in srcs:
                    if (nid, t, s) in present:  # 相互リンクは下側に出さない
                        continue
                    sp = id_to_path[s]
                    new_down[t].append((by_path[sp].title, _rel(n.path.parent, sp), None))
        n.down = new_down
        if extra:
            n.down[_EXTRA] = extra

    _save_state(root, present)

    changed = 0
    for n in notes:
        new_text = render_note(n)
        if new_text != n.path.read_text(encoding="utf-8"):
            n.path.write_text(new_text, encoding="utf-8")
            changed += 1
    return changed


def update_one(file_path, root) -> str:
    """保存時 sync。現状は vault 全体を 1 パス（個人規模を想定）。"""
    changed = sync_vault(root)
    if changed:
        return f"yurii_PKM: v2 synced {changed} file(s)"
    return "yurii_PKM: no changes"


# ---------------------------------------------------------------------------
# new note
# ---------------------------------------------------------------------------

def make_new(path, title: str = "") -> Path:
    p = Path(path)
    ts = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    t = title.strip() or p.stem
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(f"---\ntime: {ts}\ntitle: {t}\n---\n\n# {t}\n\n\n---\n", encoding="utf-8")
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
        # 作成直後に一度 sync（相方があれば下側へ反映）
        sync_vault(argv[3])
        print(str(p))
        return 0
    if mode == "retitle_links":
        # v1 互換: FILE ROOT OLD NEW。v2 は sync が表示名を現タイトルへ揃えるので
        # ROOT 全体を回すだけでよい。
        if len(argv) >= 4:
            sync_vault(argv[3])
        print("yurii_PKM: v2 retitle via sync")
        return 0
    if mode in {"update_titles", "rename_prefix", "reparent_down_children", "nf"}:
        # v2 では不要 / 非対応。呼ばれても壊さないよう no-op で返す。
        print(f"yurii_PKM: v2 ignores mode '{mode}'", file=sys.stderr)
        return 0
    print(f"unsupported mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
