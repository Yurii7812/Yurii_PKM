#!/usr/bin/env python3
"""Yurii_PKM ノート形式 v2 の parse / render / sync。

詳細仕様は repo ルートの NOTE_FORMAT.md。要点:

- ファイル名 = タイムスタンプのみ。front matter は time / title。
- 本文の後、``<!-- こっちにとって -->`` 見張り行から上側（これ＝このノートにとって そのノートが○○）。
- ``<!-- そっちにとって -->`` 見張り行から下側（それ＝そのノートにとって このノートが○○）。
  HTML コメントなのでレンダラで不可視・見出し化しない・本文と衝突しない。
- 関係: キーワード / 前提 / 論点 / 見解 / 関連 / ノート（既定）/ 自由入力。
  `カテゴリー` は選ばない ── 相手が `attribute: カテゴリー` / `attribute: キーワード`
  のどちらでも、選んだ関係に関わらず自分側は自動で `カテゴリー:` になる
  （`キーワード` 自体はピッカーから選べる。索引語の自由入力という既存の用途は変わらない）。
  `関連` は対称。並び順は カテゴリー → キーワード → 前提 → 論点 → 見解 → 関連 → ノート。
  相手が `attribute: カテゴリー` / `attribute: キーワード` のノートなら、自分側の
  ラベルは値に関わらず常に `カテゴリー:`（相手側の そっちにとって は書かれた関係のまま）。
  自分が `attribute: カテゴリー` なら、相手側の そっちにとって も常に `カテゴリー:`
  （サブ容器として）。自分が `attribute: キーワード` の場合はこの上書きをしない ──
  相手の そっちにとって には書かれた関係がそのまま出る（キーワードは「何に索引されて
  いるか」を見せるだけで、相手を自分の下位に置く容器ではないため）。
- ノード属性は front matter の `attribute: カテゴリー` / `attribute: キーワード`
  （容器ノート・索引ノードの印）。無ければただのノート。
  論点 / 見解 等は宣言しない（関係とタイトルから分かる）。
- リンク 1 本は ``関係: [t](x.md)`` のインライン、2 本以上は ``関係:`` 改行のブロック。
- 上側が真実。下側は他ノートの上側から導出。上下どちらも編集でき、
  片面の追加 / 削除はもう片面へ反映される（``.pkm_sync_state_v2.json`` で判定）。
- 本文（散文）中のリンクは、明示の関係が無ければ相手の下側に
  ``バックリンク:`` として現れる。

sync が書き換えるのは見張りコメント 2 行を持つノートだけ。旧 v1 / 旧 `---` /
日記 / 素の散文は触らない。旧形式の一括変換は `migrate` で明示的に行う。

CLI:
    note_format_v2.py update      ROOT
    note_format_v2.py update_one  FILE ROOT
    note_format_v2.py new         FILE ROOT [TITLE]
    note_format_v2.py migrate     ROOT [FILE]
    note_format_v2.py dupcheck    DIR_A DIR_B
"""
from __future__ import annotations

import datetime as _dt
import json
import os
import re
import sys
from pathlib import Path

RELATIONS: tuple[str, ...] = ("カテゴリー", "キーワード", "前提", "論点", "見解", "ノート", "関連", "補足", "資料")
# 関係名の読み替え（既定は無し。カテゴリー: はそのまま残す）
RELATION_ALIASES: dict[str, str] = {"ワード": "キーワード"}
# ノード属性: `attribute: カテゴリー` / `attribute: キーワード`（容器ノート・索引ノードの印）。
ATTR_KEYS = ("attribute", "属性")
CATEGORY_ATTR = "カテゴリー"  # attribute の値 / 関係名でもある
KEYWORD_ATTR = "キーワード"  # attribute の値 / 関係名でもある
ATTR_LABELS: frozenset[str] = frozenset({CATEGORY_ATTR, KEYWORD_ATTR})  # attribute として使える値
# 対称関係: 上側には出さず、両ノートの下側に現れる。
SYMMETRIC: frozenset[str] = frozenset({"関連"})
BACKLINK = "バックリンク"

UP_MARK = "<!-- こっちにとって -->"
DOWN_MARK = "<!-- そっちにとって -->"
# 旧見張り（している/されている）。parse だけが読む。render は新表記に統一する。
LEGACY_UP_MARK = "<!-- している -->"
LEGACY_DOWN_MARK = "<!-- されている -->"

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


def _fm_attr(fm: list[str]) -> str:
    keys = "|".join(ATTR_KEYS)
    for ln in fm:
        m = re.match(rf"^\s*(?:{keys})\s*:\s*(.+?)\s*$", ln)
        if m:
            return m.group(1).strip().strip("\"'")
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
            cur = RELATION_ALIASES.get(m.group(1).strip(), m.group(1).strip())
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
    kind = "カテゴリー" if base in ("index.md", "index") else "関連"  # v1 の Index -> カテゴリー
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
            _r = RELATION_ALIASES.get(tm.group(1).strip(), tm.group(1).strip())
            zone = ("rel", _r)
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

    # sync が触るのは見張りコメント 2 行を持つファイルだけ。
    # それ以外（旧 v1 / 旧 --- / 日記 / 素の散文）は managed=False で読むだけ。
    # 見張りは新表記（こっちにとって/そっちにとって）・旧表記（している/されている）
    # のどちらでも読める。render は常に新表記で書き直す（＝次の sync で自動移行）。
    up_mark = UP_MARK if UP_MARK in stripped else (LEGACY_UP_MARK if LEGACY_UP_MARK in stripped else None)
    down_mark = DOWN_MARK if DOWN_MARK in stripped else (LEGACY_DOWN_MARK if LEGACY_DOWN_MARK in stripped else None)
    marked = up_mark is not None and down_mark is not None
    frozen = bool(re.search(
        r"^\s*(pkm\s*:\s*raw|sync\s*:\s*(?:false|off|no))\s*$",
        "\n".join(fm), re.I | re.M))

    if not marked or frozen:
        body = list(rest)
        while body and body[-1].strip() == "":
            body.pop()
        return Note(p, fm, title, body, {}, {}, managed=False)

    u = len(stripped) - 1 - stripped[::-1].index(up_mark)
    d = len(stripped) - 1 - stripped[::-1].index(down_mark)
    if u > d:
        u = stripped.index(up_mark)
    # 本文は 1 行も削らない。見張りの直前に空いている行は「書くための余白」で、
    # テンプレートが意図して置いたもの（カーソルはそこに来る）。
    body = list(rest[:u])
    _, up = _parse_sections(rest[u + 1: d], allow_body=False)
    _, down = _parse_sections(rest[d + 1:], allow_body=False)
    return Note(p, fm, title, body, up, down)


def migrate_note(text: str, path: str = "note.md") -> str | None:
    """旧形式（v1 の Parent:/Child:/BackLink: / 旧 `---` v2）を v2 テキストへ変換。

    既に見張りコメントがある / 旧形式と認識できない場合は None。
    """
    raw = text.split("\n")
    fm, rest = _split_front_matter(raw)
    stripped = [ln.strip() for ln in rest]
    if (UP_MARK in stripped and DOWN_MARK in stripped) or (
            LEGACY_UP_MARK in stripped and LEGACY_DOWN_MARK in stripped):
        return None
    title = _fm_title(fm) or Path(path).stem
    div_idx = [i for i, s in enumerate(stripped) if DIVIDER_RE.match(s)]

    if len(div_idx) >= 2 and (
        _has_relation_header(rest[div_idx[-2] + 1:])
        or all(x == "" for x in stripped[div_idx[-2] + 1:])
    ):
        body_lines = rest[:div_idx[-2]]
        _, up = _parse_sections(rest[div_idx[-2] + 1: div_idx[-1]], allow_body=False)
        _, down = _parse_sections(rest[div_idx[-1] + 1:], allow_body=False)
    elif len(div_idx) == 1 and (
        _has_relation_header(rest[div_idx[0] + 1:])
        or all(x == "" for x in stripped[div_idx[0] + 1:])
    ):
        body_lines = rest[:div_idx[0]]
        _, up = _parse_sections(rest[div_idx[0] + 1:], allow_body=False)
        down = {}
    elif any(LEGACY_HDR_RE.match(s) for s in stripped):
        body_lines, up, down = _migrate_legacy(rest)
    else:
        return None

    body = list(body_lines)
    while body and body[-1].strip() == "":
        body.pop()
    return render_note(Note(Path(path), fm, title, body, up, down))


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
    """常にブロック形で書く。

        ラベル:
        [表示名](target.md)

    1 本でもインラインにしない。増えたときに行の形が変わらず、追記が
    「1 行足すだけ」で済むため。読み込み側はインライン形も受け付ける。
    """
    if not entries:
        return []
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
    """本文はユーザーのもの。空行を含めてそのまま通す。

    整形するのは見張りコメント以降（関係セクション）だけ。本文の空行を
    潰すと、テンプレートが置いた「書くための余白」が毎回消えてしまう。
    """
    out: list[str] = list(note.fm)
    body = list(note.body)
    # front matter の直後は 1 行空ける（本文が既に空行始まりならそれを使う）
    if not body or body[0].strip() != "":
        out.append("")
    out += body

    # 本文 → こっちにとって見張り → 上側 → そっちにとって見張り → 下側
    # 本文が空行で終わっていなければ 1 行だけ空ける（余白があるならそのまま）
    if out and out[-1].strip() != "":
        out.append("")
    out.append(UP_MARK)
    out += _squeeze_blanks(_render_group(note.up))
    out.append(DOWN_MARK)
    out += _squeeze_blanks(_render_group(note.down, is_down=True))

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


def _load_state(root: Path) -> set[tuple]:
    """有向関係 = `from\\tto`（2 要素）、対称関係 = `a\\t関連\\tb`（3 要素）。"""
    fp = root / _STATE_FILE
    if not fp.exists():
        return set()
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        out: set[tuple] = set()
        for x in data:
            if not isinstance(x, str):
                continue
            parts = x.split("\t")
            if len(parts) in (2, 3):
                out.add(tuple(parts))
        return out
    except Exception:  # noqa: BLE001
        return set()


def _save_state(root: Path, entries: set[tuple]) -> None:
    fp = root / _STATE_FILE
    payload = sorted("\t".join(r) for r in entries)
    fp.write_text(json.dumps(payload, ensure_ascii=False, indent=0), encoding="utf-8")


def sync_vault(root) -> int:
    """vault 全体を 1 パスで整合させる。見張りコメントを持つノートだけを書き換える。"""
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

    # 有向関係の同一性は (from_id, to_id) のペア。ラベルは別管理（表示のみ）。
    up_label: dict[tuple[str, str], str] = {}    # (A,B) <- A の こっちにとって 行 `label: [B]`
    down_label: dict[tuple[str, str], str] = {}  # (A,B) <- B の そっちにとって 行 `label: [A]`
    up_ann: dict[tuple[str, str], str] = {}
    up_unresolved: dict[Path, dict[str, list]] = {k: {} for k in by_path}
    body_links: dict[str, set[str]] = {}
    sym_face: dict[tuple[str, frozenset], set[str]] = {}  # (関係, {id,id}) -> 端点

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
                if t in SYMMETRIC:
                    if tid != sid:
                        sym_face.setdefault((t, frozenset((sid, tid))), set()).add(sid)
                    continue
                up_label[(sid, tid)] = t
                if ann:
                    up_ann[(sid, tid)] = ann
        for t, entries in n.down.items():
            if t in _RESERVED:
                continue
            for _ti, tg, _ann in entries:
                src_id = rid(tg, n.path.parent)
                if src_id is None:
                    continue
                if t in SYMMETRIC:
                    if src_id != sid:
                        sym_face.setdefault((t, frozenset((sid, src_id))), set()).add(sid)
                    continue
                down_label[(src_id, sid)] = t
        bl: set[str] = set()
        for tg in _links_in(n.body):
            tid = rid(tg, n.path.parent)
            if tid is not None and tid != sid:
                bl.add(tid)
        body_links[sid] = bl

    prev = _load_state(root)
    prev_pairs = {(a, b) for r in prev if len(r) == 2 for a, b in [r]}
    prev_pairs |= {(r[0], r[2]) for r in prev if len(r) == 3 and r[1] not in SYMMETRIC}
    prev_sym = {r for r in prev if len(r) == 3 and r[1] in SYMMETRIC}

    # --- 有向関係の解決（ペア単位） ---
    present: set[tuple[str, str]] = set()
    for pair in set(up_label) | set(down_label) | prev_pairs:
        up_face = pair in up_label
        down_face = pair in down_label
        if up_face and down_face:
            present.add(pair)
        elif (up_face != down_face) and pair not in prev_pairs:
            present.add(pair)  # 片面だけ & 前回に無い = 今追加
    present = {p for p in present if p[0] in id_to_path and p[1] in id_to_path}

    # --- 対称関係（関連） ---
    present_sym: set[Rel] = set()
    for (t, pair), faces in sym_face.items():
        a, b = sorted(pair)
        if a not in id_to_path or b not in id_to_path:
            continue
        if len(faces) >= 2 or (len(faces) == 1 and (a, t, b) not in prev_sym):
            present_sym.add((a, t, b))

    directed = set(present)
    directed |= {(a, b) for (a, _t, b) in present_sym}
    directed |= {(b, a) for (a, _t, b) in present_sym}

    attr_of: dict[str, str] = {
        i: a for kk, nn in by_path.items()
        if (i := ids.get(kk)) is not None and (a := _fm_attr(nn.fm)) in ATTR_LABELS
    }

    def far_label(pair: tuple[str, str]) -> str:
        return down_label.get(pair) or up_label.get(pair) or "ノート"

    # --- 上側を再構築。相手が attribute 持ちなら自分側ラベルは常に `カテゴリー:` ---
    incoming: dict[str, list[tuple[str, str]]] = {}  # to_id -> [(from_id, label)]
    for (a, b) in present:
        # from が attribute: カテゴリー = サブ容器 → 相手（to）の そっちにとって では
        # `カテゴリー:`。from が attribute: キーワード の場合はここでは上書きしない
        # （キーワード自身の下側は「中身が何の関係か」を見せる面。to 自身の下側も同様に
        # 上書きしない ── to の attribute では上書きしない）。
        lbl = CATEGORY_ATTR if attr_of.get(a) == CATEGORY_ATTR else far_label((a, b))
        incoming.setdefault(b, []).append((a, lbl))

    for k, n in by_path.items():
        sid = ids.get(k)
        if sid is None:
            continue
        # 相手（b）が attribute 持ち（カテゴリー / キーワードどちらでも）なら、
        # 値に関わらず自分の こっちにとって は常に `カテゴリー:`。
        outgoing = [(b, (CATEGORY_ATTR if b in attr_of else far_label((sid, b))))
                    for (a, b) in present if a == sid]
        # 既存の並び順と、手で打った表示名を尊重
        order: list[str] = []
        orig_title: dict[str, str] = {}
        for t, es in n.up.items():
            if t == _EXTRA:
                continue
            for _ti, tg, _a in es:
                r = rid(tg, n.path.parent)
                if r:
                    order.append(r)
                    orig_title.setdefault(r, _ti)
        outgoing.sort(key=lambda x: order.index(x[0]) if x[0] in order else 1_000_000)
        new_up: dict[str, list] = {}
        for tid, lbl in outgoing:
            tp = id_to_path[tid]
            tn = by_path.get(tp)
            if tn is not None and tn.managed:
                disp = tn.title  # 管理下は現タイトルへ追従
            else:  # 外部 / 凍結ノートは打った表示名を尊重
                disp = orig_title.get(tid) or (tn.title if tn else Path(tid).stem)
            new_up.setdefault(lbl, []).append(
                (disp, _rel(n.path.parent, tp), up_ann.get((sid, tid))))
        for t, es in up_unresolved[k].items():
            for e in es:
                new_up.setdefault(t, []).append(e)
        if n.up.get(_EXTRA):
            new_up[_EXTRA] = n.up[_EXTRA]
        n.up = new_up

    # --- 下側を再構築（関係 + 対称 + バックリンク） ---
    for k, n in by_path.items():
        nid = ids.get(k)
        new_down: dict[str, list] = {}
        if nid is not None:
            # 下側（子リスト）の表示名は、既に手で付けた表示名があればそれを尊重する
            # （タイトルへ追従するのは上側だけ。子の表示名を変えても、次の sync で
            # 相手の現タイトルへ勝手に戻ってしまわないようにする）。
            orig_down_title: dict[str, str] = {}
            for t, es in n.down.items():
                if t in _RESERVED:
                    continue
                for _ti, tg, _ann in es:
                    r = rid(tg, n.path.parent)
                    if r:
                        orig_down_title.setdefault(r, _ti)

            by_lbl: dict[str, list[str]] = {}
            for (a, lbl) in incoming.get(nid, []):
                if (nid, a) in present:  # 相互は下側に出さない
                    continue
                by_lbl.setdefault(lbl, []).append(a)
            for (a, t, b) in present_sym:
                other = b if a == nid else (a if b == nid else None)
                if other is not None:
                    by_lbl.setdefault(t, []).append(other)
            for lbl, srcs in by_lbl.items():
                new_down[lbl] = [
                    (orig_down_title.get(s) or by_path[id_to_path[s]].title,
                     _rel(n.path.parent, id_to_path[s]), None)
                    for s in sorted(set(srcs))
                ]
            back = sorted(
                s for s, targets in body_links.items()
                if nid in targets and (s, nid) not in directed
                and (nid, s) not in directed and s in id_to_path
            )
            if back:
                new_down[BACKLINK] = [
                    (by_path[id_to_path[s]].title, _rel(n.path.parent, id_to_path[s]), None)
                    for s in back
                ]
        if n.down.get(_EXTRA):
            new_down[_EXTRA] = n.down[_EXTRA]
        n.down = new_down

    _save_state(root, set(present) | present_sym)

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
    if mode == "migrate":
        # 明示的な変換。sync は旧形式を触らないので、これを 1 回走らせて v2 化する。
        if len(argv) < 3:
            print("usage: note_format_v2.py migrate ROOT [FILE]", file=sys.stderr)
            return 2
        root = Path(argv[2]).resolve()
        targets = [Path(argv[3])] if len(argv) > 3 else list(_iter_md(root))
        done = 0
        for tp in targets:
            try:
                cur = tp.read_text(encoding="utf-8")
            except OSError:
                continue
            new = migrate_note(cur, str(tp))
            if new and new != cur:
                tp.write_text(new, encoding="utf-8")
                done += 1
        if done:
            sync_vault(root)
        print(f"yurii_PKM: v2 migrated {done} file(s)")
        return 0
    if mode == "dupcheck":
        # 2 つの vault を merge する前に、同名 .md（＝タイムスタンプ衝突）を洗い出す。
        if len(argv) < 4:
            print("usage: note_format_v2.py dupcheck DIR_A DIR_B", file=sys.stderr)
            return 2
        a = {p.name for p in Path(argv[2]).rglob("*.md")} - {"index.md"}
        b = {p.name for p in Path(argv[3]).rglob("*.md")} - {"index.md"}
        dup = sorted(a & b)
        if dup:
            print("衝突するファイル名（merge 前にどちらかを改名）:")
            for name in dup:
                print(f"  {name}")
            return 1
        print("衝突なし（index.md を除く）")
        return 0
    if mode in {"update_titles", "rename_prefix", "reparent_down_children", "nf"}:
        print(f"yurii_PKM: v2 ignores mode '{mode}'", file=sys.stderr)
        return 0
    print(f"unsupported mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
