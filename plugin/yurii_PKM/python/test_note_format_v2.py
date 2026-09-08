#!/usr/bin/env python3
"""note_format_v2 の自己完結テスト（pytest 非依存）。

    python3 test_note_format_v2.py
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import note_format_v2 as v2

_FAILED: list[str] = []


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FAIL {msg}")
        _FAILED.append(msg)


def regions(text: str) -> tuple[str, str]:
    """(上側リージョン, 下側リージョン) を返す。末尾側の --- 2 本で区切る。"""
    lines = text.split("\n")
    try:
        fm_end = lines.index("---", 1)
    except ValueError:
        fm_end = -1
    idx = [i for i in range(fm_end + 1, len(lines)) if lines[i].strip() == "---"]
    if len(idx) < 2:
        return "", ""
    a, b = idx[-2], idx[-1]
    return "\n".join(lines[a + 1:b]), "\n".join(lines[b + 1:])


def note(path: Path, title: str, up: str = "", down: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    txt = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n本文。\n\n---\n"
    if up:
        txt += up.strip("\n") + "\n"
    txt += "---\n"
    if down:
        txt += down.strip("\n") + "\n"
    path.write_text(txt, encoding="utf-8")


# ---------------------------------------------------------------------------

def test_parse_inline_and_block_roundtrip() -> None:
    print("parse: インライン / ブロックの往復")
    src = (
        "---\ntime: 2026-01-01 00:00:00\ntitle: A\n---\n\n# A\n\n"
        "散文。ここに ワード: と書いても本文。\n\n"
        "---\n"
        "カテゴリー: [瞑想](20250101.md)\n"
        "論点:\n[問い](20250111.md) — メモ\n[別の問い](20250112.md)\n"
        "---\n"
        "関連: [呼吸法](20250107.md)\n"
    )
    n = v2.parse_note(Path("/x/A.md"), src)
    check(n.title == "A", "title を front matter から取得")
    check("ワード:" in "\n".join(n.body), "本文の『ワード:』は本文のまま（型にしない）")
    check(n.up["カテゴリー"] == [("瞑想", "20250101.md", None)], "インライン 1 本")
    check(len(n.up["論点"]) == 2, "ブロック 2 本")
    check(n.up["論点"][0][2] == "メモ", "注釈を保持")
    check(n.down["関連"] == [("呼吸法", "20250107.md", None)], "下側インライン")
    out = v2.render_note(n)
    check("カテゴリー: [瞑想](20250101.md)" in out, "1 本はインラインで出力")
    check("論点:\n[問い](20250111.md) — メモ" in out, "2 本はブロックで出力")
    lines = out.split("\n")
    after_fm = lines[lines.index("---", 1) + 1:]
    check(after_fm.count("---") == 2, "本文以降の構造マーカー --- は 2 本")


def test_normalize_counts() -> None:
    print("normalize: 本数に応じた整形")
    src = (
        "---\ntitle: A\n---\n\n# A\n\n"
        "---\n"
        "論点: [x](20250101.md)\n[y](20250102.md)\n"  # インライン記法だが 2 本
        "前提:\n[z](20250103.md)\n"                     # ブロック記法だが 1 本
        "---\n"
    )
    n = v2.parse_note(Path("/x/A.md"), src)
    out = v2.render_note(n)
    check("論点:\n[x](20250101.md)\n[y](20250102.md)" in out, "2 本 → ブロックへ")
    check("前提: [z](20250103.md)" in out, "1 本 → インラインへ")


def test_sync_generates_down() -> None:
    print("sync: 上側 → 相方の下側 生成")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "集中と気づき", up="論点: [問い](20250111.md)")
        note(root / "20250111.md", "瞑想のコツがわからない")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("論点: [集中と気づき](20250104.md)" in dn, "B の下側に『論点: A』が入る")


def test_sync_symmetric_down_edit() -> None:
    print("sync: 下側の手編集 → 相方の上側へ反映")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A")
        note(root / "20250120.md", "C", down="関連: [A](20250104.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("関連: [C](20250120.md)" in up, "A の上側に『関連: C』が入る")


def test_sync_delete_from_down_removes_up() -> None:
    print("sync: 下側から削除 → 相方の上側からも消える")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="論点: [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        b_path = root / "20250111.md"
        check("論点: [A](20250104.md)" in regions(b_path.read_text(encoding="utf-8"))[1], "まず下側に生成")
        # ユーザが B の下側から論点行を削除
        b_path.write_text(
            "---\ntitle: B\n---\n\n# B\n\n本文。\n\n---\n", encoding="utf-8"
        )
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("20250111.md" not in up, "A の上側から論点リンクが消える")


def test_mutual_link_not_shown_in_down() -> None:
    print("sync: 相互リンクは下側に出さない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="関連: [B](20250111.md)")
        note(root / "20250111.md", "B", up="関連: [A](20250104.md)")
        v2.sync_vault(root)
        a_down = regions((root / "20250104.md").read_text(encoding="utf-8"))[1]
        b_down = regions((root / "20250111.md").read_text(encoding="utf-8"))[1]
        check("20250111.md" not in a_down, "A の下側に B は出ない")
        check("20250104.md" not in b_down, "B の下側に A は出ない")


def test_title_refresh() -> None:
    print("sync: リンク表示名を相手の現タイトルへ更新")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="論点: [ふるいタイトル](20250111.md)")
        note(root / "20250111.md", "新しいタイトル")
        v2.sync_vault(root)
        a = (root / "20250104.md").read_text(encoding="utf-8")
        check("[新しいタイトル](20250111.md)" in a, "表示名が front matter の title に揃う")


def test_subdir_relative_path() -> None:
    print("sync: サブフォルダ間は相対パス")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="関連: [B](sub/20250111.md)")
        note(root / "sub" / "20250111.md", "B")
        v2.sync_vault(root)
        b = (root / "sub" / "20250111.md").read_text(encoding="utf-8")
        check("[A](../20250104.md)" in b, "B から見て ../ 付きで生成")


def test_new_skeleton() -> None:
    print("new: 骨組み生成")
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "20260909120000.md"
        v2.make_new(p, "テスト")
        txt = p.read_text(encoding="utf-8")
        check(txt.startswith("---\ntime: "), "front matter で始まる")
        check("# テスト" in txt, "H1 を含む")
        check(txt.rstrip().endswith("---\n---"), "末尾に --- が 2 本")



def test_migrate_legacy_v1_note() -> None:
    print("migrate: 旧 v1 (Parent/Child/BackLink) を v2 へ寄せる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "260909061513.md").write_text(
            "---\ntitle: parent-note\n---\n\n# parent-note\n\n---\n---\n", encoding="utf-8")
        legacy = (
            "---\ntime: 2026-09-09 06:15:21\ntitle: 260909061521\n---\n\n"
            "# 260909061521\n\n\n\nParent:\n[260909061513](260909061513.md)\n"
            "Child:\nBackLink:\n[Index](index.md)\n"
        )
        p = root / "260909061521.md"
        p.write_text(legacy, encoding="utf-8")
        v2.sync_vault(root)
        txt = p.read_text(encoding="utf-8")
        up, dn = regions(txt)
        check("Parent:" not in txt and "Child:" not in txt and "BackLink:" not in txt,
              "旧見出しが消える")
        check("関連: [parent-note](260909061513.md)" in up, "Parent リンク -> 関連: (表示名は現タイトルへ)")
        check("カテゴリー: [Index](index.md)" in up, "[Index] -> カテゴリー:")
        ls = txt.split("\n"); af = ls[ls.index("---", 1) + 1:]
        check(af.count("---") == 2, "本文以降の構造マーカー --- は 2 本")



def test_kenkai_and_custom_type() -> None:
    print("type: 見解 と自由入力の型")
    src = ("---\ntitle: A\n---\n\n# A\n\n本文。\n\n---\n"
           "見解: [x](20250101.md)\n補足: [y](20250102.md)\n---\n")
    n = v2.parse_note(Path("/x/A.md"), src)
    check(n.up.get("見解") == [("x", "20250101.md", None)], "見解: を型として認識")
    check(n.up.get("補足") == [("y", "20250102.md", None)], "自由な語:( 補足 ) も型として保持")
    out = v2.render_note(n)
    check("見解: [x](20250101.md)" in out and "補足: [y](20250102.md)" in out, "両方 round-trip")


def test_body_link_becomes_backlink() -> None:
    print("backlink: 本文中のリンク -> 相手の バックリンク:")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "20250104.md").write_text(
            "---\ntitle: A\n---\n\n# A\n\n詳しくは [B の話](20250111.md) を参照。\n\n---\n---\n",
            encoding="utf-8")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        up, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("バックリンク: [A](20250104.md)" in dn, "B の下側に バックリンク: A")
        check("関連:" not in dn and "論点:" not in dn, "型セクションには入らない")


def test_typed_link_suppresses_backlink() -> None:
    print("backlink: 型付きの関係があれば バックリンク: にしない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "20250104.md").write_text(
            "---\ntitle: A\n---\n\n# A\n\n本文で [B](20250111.md) に触れる。\n\n---\n"
            "論点: [B](20250111.md)\n---\n", encoding="utf-8")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        _up, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("論点: [A](20250104.md)" in dn, "論点: A は出る")
        check("バックリンク" not in dn, "バックリンク: A は出さない（型で表示済み）")


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
    print()
    if _FAILED:
        print(f"{len(_FAILED)} FAILED")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
