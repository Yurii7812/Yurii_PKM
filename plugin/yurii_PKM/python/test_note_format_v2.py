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


UP_MARK = "<!-- こっちにとって -->"
DOWN_MARK = "<!-- そっちにとって -->"


def regions(text: str) -> tuple[str, str]:
    """(上側リージョン, 下側リージョン) を返す。見張りコメント行で区切る。"""
    lines = text.split("\n")
    sl = [l.strip() for l in lines]
    if UP_MARK not in sl or DOWN_MARK not in sl:
        return "", ""
    u, d = sl.index(UP_MARK), sl.index(DOWN_MARK)
    return "\n".join(lines[u + 1:d]), "\n".join(lines[d + 1:])


def note(path: Path, title: str, up: str = "", down: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    txt = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n本文。\n\n{UP_MARK}\n"
    if up:
        txt += up.strip("\n") + "\n"
    txt += DOWN_MARK + "\n"
    if down:
        txt += down.strip("\n") + "\n"
    path.write_text(txt, encoding="utf-8")


# ---------------------------------------------------------------------------

def test_parse_inline_and_block_roundtrip() -> None:
    print("parse: インライン / ブロックの往復")
    src = (
        "---\ntime: 2026-01-01 00:00:00\ntitle: A\n---\n\n# A\n\n"
        "散文。ここに ワード: と書いても本文。ここに --- も書ける。\n\n"
        "<!-- こっちにとって -->\n"
        "所属: [瞑想](20250101.md)\n"
        "論点:\n[問い](20250111.md) — メモ\n[別の問い](20250112.md)\n"
        "<!-- そっちにとって -->\n"
        "関連: [呼吸法](20250107.md)\n"
    )
    n = v2.parse_note(Path("/x/A.md"), src)
    check(n.title == "A", "title を front matter から取得")
    check("ワード:" in "\n".join(n.body), "本文の『ワード:』は本文のまま（型にしない）")
    check(n.up["所属"] == [("瞑想", "20250101.md", None)], "インライン 1 本")
    check(len(n.up["論点"]) == 2, "ブロック 2 本")
    check(n.up["論点"][0][2] == "メモ", "注釈を保持")
    check(n.down["関連"] == [("呼吸法", "20250107.md", None)], "下側インライン")
    out = v2.render_note(n)
    check("所属:\n[瞑想](20250101.md)" in out, "1 本もブロックで出力")
    check("論点:\n[問い](20250111.md) — メモ" in out, "2 本はブロックで出力")
    check(UP_MARK in out and DOWN_MARK in out, "見張りコメントが両方ある")
    check(out.count("\n---\n") == 1, "--- は front matter の 1 箇所だけ（本文の --- は保持）")


def test_normalize_counts() -> None:
    print("normalize: 本数に応じた整形")
    src = (
        "---\ntitle: A\n---\n\n# A\n\n"
        "<!-- こっちにとって -->\n"
        "論点: [x](20250101.md)\n[y](20250102.md)\n"  # インライン記法だが 2 本
        "前提:\n[z](20250103.md)\n"                     # ブロック記法だが 1 本
        "<!-- そっちにとって -->\n"
    )
    n = v2.parse_note(Path("/x/A.md"), src)
    out = v2.render_note(n)
    check("論点:\n[x](20250101.md)\n[y](20250102.md)" in out, "2 本 → ブロックへ")
    check("前提:\n[z](20250103.md)" in out, "1 本もブロックのまま")


def test_sync_generates_down() -> None:
    print("sync: 上側 → 相方の下側 生成")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "集中と気づき", up="論点: [問い](20250111.md)")
        note(root / "20250111.md", "瞑想のコツがわからない")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("論点:\n[集中と気づき](20250104.md)" in dn, "B の下側に『論点: A』が入る")


def test_sync_symmetric_down_edit() -> None:
    print("sync: 下側の手編集（有向）→ 相方の上側へ反映")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A")
        note(root / "20250120.md", "C", down="論点: [A](20250104.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("論点:\n[C](20250120.md)" in up, "A の上側に『論点: C』が入る")


def test_kanren_down_edit_mirrors() -> None:
    print("sync: 関連 を下側に手書き → 相方の下側にも入る")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A")
        note(root / "20250120.md", "C", down="関連: [A](20250104.md)")
        v2.sync_vault(root)
        _u, a_dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("関連:\n[C](20250120.md)" in a_dn, "A の下側に 関連: C")


def test_sync_delete_from_down_removes_up() -> None:
    print("sync: 下側から削除 → 相方の上側からも消える")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="論点: [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        b_path = root / "20250111.md"
        check("論点:\n[A](20250104.md)" in regions(b_path.read_text(encoding="utf-8"))[1], "まず下側に生成")
        # ユーザが B の下側から論点行を削除
        b_path.write_text(
            "---\ntitle: B\n---\n\n# B\n\n本文。\n\n---\n", encoding="utf-8"
        )
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("20250111.md" not in up, "A の上側から論点リンクが消える")


def test_kanren_is_symmetric() -> None:
    print("sync: 関連 は対称（両方の下側に出る、上側には出ない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="関連: [B](20250111.md)")  # 旧スタイルの上側
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        a_up, a_dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        b_up, b_dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("関連:\n[B](20250111.md)" in a_dn, "A の下側に 関連: B")
        check("関連:\n[A](20250104.md)" in b_dn, "B の下側に 関連: A")
        check("関連" not in a_up and "関連" not in b_up, "どちらの上側にも 関連 は無い")


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
        check(txt.rstrip().endswith(UP_MARK + "\n" + DOWN_MARK), "末尾に見張りコメント 2 行")



def test_migrate_legacy_v1_note() -> None:
    print("migrate: 旧 v1 (Parent/Child/BackLink) を v2 へ寄せる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "260909061513.md").write_text(
            "---\ntitle: parent-note\n---\n\n# parent-note\n\n<!-- こっちにとって -->\n<!-- そっちにとって -->\n", encoding="utf-8")
        legacy = (
            "---\ntime: 2026-09-09 06:15:21\ntitle: 260909061521\n---\n\n"
            "# 260909061521\n\n\n\nParent:\n[260909061513](260909061513.md)\n"
            "Child:\nBackLink:\n[Index](index.md)\n"
        )
        p = root / "260909061521.md"
        p.write_text(legacy, encoding="utf-8")
        v2.sync_vault(root)
        check(p.read_text(encoding="utf-8") == legacy, "sync 単体では旧 v1 を触らない")
        p.write_text(v2.migrate_note(legacy, str(p)), encoding="utf-8")
        v2.sync_vault(root)
        txt = p.read_text(encoding="utf-8")
        up, dn = regions(txt)
        check("Parent:" not in txt and "Child:" not in txt and "BackLink:" not in txt,
              "旧見出しが消える")
        check("関連:\n[parent-note](260909061513.md)" in dn, "Parent リンク -> 関連:（対称なので下側・表示名は現タイトルへ）")
        check("カテゴリー:\n[Index](index.md)" in up, "[Index] -> カテゴリー:")
        check(UP_MARK in txt and DOWN_MARK in txt, "見張りコメント形式に変換される")



def test_kenkai_and_custom_type() -> None:
    print("type: 見解 と自由入力の型")
    src = ("---\ntitle: A\n---\n\n# A\n\n本文。\n\n<!-- こっちにとって -->\n"
           "見解: [x](20250101.md)\n補足: [y](20250102.md)\n<!-- そっちにとって -->\n")
    n = v2.parse_note(Path("/x/A.md"), src)
    check(n.up.get("見解") == [("x", "20250101.md", None)], "見解: を型として認識")
    check(n.up.get("補足") == [("y", "20250102.md", None)], "自由な語:( 補足 ) も型として保持")
    out = v2.render_note(n)
    check("見解:\n[x](20250101.md)" in out and "補足:\n[y](20250102.md)" in out, "両方 round-trip")


def test_body_link_becomes_backlink() -> None:
    print("backlink: 本文中のリンク -> 相手の バックリンク:")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "20250104.md").write_text(
            "---\ntitle: A\n---\n\n# A\n\n詳しくは [B の話](20250111.md) を参照。\n\n<!-- こっちにとって -->\n<!-- そっちにとって -->\n",
            encoding="utf-8")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        up, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("バックリンク:\n[A](20250104.md)" in dn, "B の下側に バックリンク: A")
        check("関連:" not in dn and "論点:" not in dn, "型セクションには入らない")


def test_typed_link_suppresses_backlink() -> None:
    print("backlink: 型付きの関係があれば バックリンク: にしない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "20250104.md").write_text(
            "---\ntitle: A\n---\n\n# A\n\n本文で [B](20250111.md) に触れる。\n\n<!-- こっちにとって -->\n"
            "論点: [B](20250111.md)\n<!-- そっちにとって -->\n", encoding="utf-8")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        _up, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("論点:\n[A](20250104.md)" in dn, "論点: A は出る")
        check("バックリンク" not in dn, "バックリンク: A は出さない（型で表示済み）")


def test_typed_link_from_down_side_suppresses_backlink() -> None:
    print("backlink: 型付きの関係が相手の そっちにとって 側にあっても バックリンク: にしない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # A の本文で B に触れつつ、A の そっちにとって（子）側にも同じ B を載せる
        # （nc/ca 相当。関係の向きは B->A で、本文リンクの向き A->B とは逆）。
        (root / "20250104.md").write_text(
            "---\ntitle: A\n---\n\n# A\n\n本文で [B](20250111.md) に触れる。\n\n"
            "<!-- こっちにとって -->\n<!-- そっちにとって -->\nノート: [B](20250111.md)\n",
            encoding="utf-8")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        up, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("ノート:\n[A](20250104.md)" in up, "B の こっちにとって に ノート: A は出る")
        check("バックリンク" not in dn, "B の そっちにとって に バックリンク: A は出さない（重複のため）")



def test_foreign_file_untouched() -> None:
    print("integrate: 見張り無しの外部ファイル（日記）は書き換えない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        diary = root / "diary" / "2024-05-01.md"
        diary.parent.mkdir(parents=True)
        raw = ("# 2024-05-01\n\n今日は晴れ。\n\n---\n\n"
               "考えごと。ワード: これも本文。詳しくは [瞑想メモ](../20250104.md)。\n")
        diary.write_text(raw, encoding="utf-8")
        note(root / "20250104.md", "瞑想メモ")
        v2.sync_vault(root)
        check(diary.read_text(encoding="utf-8") == raw, "日記ファイルはバイト単位で不変")
        _up, dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("バックリンク:\n[2024-05-01](diary/2024-05-01.md)" in dn,
              "日記からの本文リンクは PKM 側に バックリンク として出る")


def test_pkm_raw_optout() -> None:
    print("integrate: front matter の pkm: raw で除外")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        raw = ("---\ntitle: 生ログ\npkm: raw\n---\n\n# 生ログ\n\n"
               "<!-- こっちにとって -->\n所属: [x](20250104.md)\n<!-- そっちにとって -->\n")
        p = root / "20250101.md"
        p.write_text(raw, encoding="utf-8")
        note(root / "20250104.md", "X")
        v2.sync_vault(root)
        check(p.read_text(encoding="utf-8") == raw, "見張りがあっても pkm: raw なら不変")



def test_unmarked_notes_frozen_by_sync() -> None:
    print("integrate: 見張り無し（v1 形式含む）は sync では絶対に触らない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        old = root / "diary" / "20200101120000.md"
        old.parent.mkdir(parents=True)
        v1raw = ("# 2020-01-01\n\n昔のメモ。\n\nParent:\n[何か](20200102120000.md)\n"
                 "Child:\nBackLink:\n[Index](index.md)\n")
        old.write_text(v1raw, encoding="utf-8")
        note(root / "20250104.md", "現ノート", up="論点: [昔のメモ](diary/20200101120000.md)")
        v2.sync_vault(root)
        check(old.read_text(encoding="utf-8") == v1raw, "v1 形式ノートは sync で 1 バイト不変")
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("論点:\n[昔のメモ](diary/20200101120000.md)" in up, "リンクは打った通りに残る（表示名も固定）")
        # migrate を明示的に呼ぶと変換される
        conv = v2.migrate_note(v1raw, str(old))
        check(conv is not None and "<!-- こっちにとって -->" in conv, "migrate は v2 化する")


def test_legacy_marks_upgraded_by_sync() -> None:
    print("integrate: 旧見張り（している/されている）は sync で新表記へ書き換わる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        legacy = (
            "---\ntime: 2026-01-01 00:00:00\ntitle: A\n---\n\n# A\n\n本文。\n\n"
            f"{v2.LEGACY_UP_MARK}\n論点: [B](20250111.md)\n{v2.LEGACY_DOWN_MARK}\n"
        )
        p = root / "20250104.md"
        p.write_text(legacy, encoding="utf-8")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        txt = p.read_text(encoding="utf-8")
        check(v2.LEGACY_UP_MARK not in txt and v2.LEGACY_DOWN_MARK not in txt,
              "旧見張りは残らない")
        check(UP_MARK in txt and DOWN_MARK in txt, "新見張りに書き換わる")
        check("論点:\n[B](20250111.md)" in txt, "関係の中身は保持される")


def _note_with_attr(path: Path, title: str, attr: str, up: str = "", down: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    txt = (
        f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\nattribute: {attr}\n---\n\n"
        f"# {title}\n\n本文。\n\n{UP_MARK}\n"
    )
    if up:
        txt += up.strip("\n") + "\n"
    txt += DOWN_MARK + "\n"
    if down:
        txt += down.strip("\n") + "\n"
    path.write_text(txt, encoding="utf-8")


def test_attribute_category_labels_member_up_side() -> None:
    print("attribute: カテゴリー は非対称：メンバー側の上側だけ常に カテゴリー: になる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _note_with_attr(root / "20250101.md", "哲学", v2.CATEGORY_ATTR)
        note(root / "20250104.md", "認識論とは何か", up="論点: [哲学](20250101.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _u, dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("カテゴリー:\n[哲学](20250101.md)" in up,
              "手で 論点 を選んでいても、相手が カテゴリー なら上側は カテゴリー:")
        check("論点:\n[認識論とは何か](20250104.md)" in dn,
              "容器ノート自身の下側は非対称：自分（メンバー）が容器でないので元の関係名（論点:）のまま")


def test_attribute_category_subcategory_labels_down_side_too() -> None:
    print("自分（サブ容器）も attribute: カテゴリー なら、相手の下側も カテゴリー: になる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _note_with_attr(root / "20250101.md", "哲学", v2.CATEGORY_ATTR)
        _note_with_attr(root / "20250104.md", "認識論", v2.CATEGORY_ATTR,
                         up="ノート: [哲学](20250101.md)")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("カテゴリー:\n[認識論](20250104.md)" in dn,
              "自分もカテゴリーノードなので、相手の下側も カテゴリー: になる（サブ容器）")


def test_attribute_keyword_target_forces_category_not_keyword() -> None:
    print("相手が attribute: キーワード でも、自分の上側は キーワード: ではなく カテゴリー: になる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _note_with_attr(root / "20250101.md", "実在論", v2.KEYWORD_ATTR)
        note(root / "20250104.md", "普遍は実在するか", up="資料: [実在論](20250101.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _u, dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("カテゴリー:\n[実在論](20250101.md)" in up,
              "手で 資料 を選んでいても、相手が キーワード ノードなら上側は カテゴリー:（キーワード: にはならない）")
        check("資料:\n[普遍は実在するか](20250104.md)" in dn,
              "実在論 側の下側は打った関係名（資料:）のまま。キーワードは相手を下位に置く容器ではない")


def test_attribute_keyword_source_does_not_force_target_down_side() -> None:
    print("自分が attribute: キーワード でも、相手の下側は上書きしない（打った関係名のまま）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250101.md", "実在論")
        _note_with_attr(root / "20250104.md", "唯名論", v2.KEYWORD_ATTR,
                         up="関連: [実在論](20250101.md)")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("関連:\n[唯名論](20250104.md)" in dn,
              "自分（唯名論）が キーワード ノードでも、相手（実在論）の下側は打った関係名（関連:）のまま")
        check("キーワード:\n[唯名論](20250104.md)" not in dn,
              "カテゴリーと違い、キーワードのサブノードは相手の下側を キーワード: に上書きしない")


def test_attribute_keyword_child_view_differs_by_side() -> None:
    print("キーワードノードの子：キーワード側の下側は打った関係名、子自身の上側は カテゴリー:")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _note_with_attr(root / "20250101.md", "実在論", v2.KEYWORD_ATTR)
        note(root / "20250104.md", "普遍は実在するか", up="資料: [実在論](20250101.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _u, dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("資料:\n[普遍は実在するか](20250104.md)" in dn,
              "実在論（キーワード）側の下側からは、打った関係名（資料:）で見える")
        check("カテゴリー:\n[実在論](20250101.md)" in up,
              "その子（普遍は実在するか）自身の上側からは カテゴリー: として見える")


def test_down_side_display_name_is_sticky() -> None:
    print("下側（子リスト）の表示名は手で変えたらそのまま残る（相手のタイトルへ戻らない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="論点: [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("論点:\n[A](20250104.md)" in dn, "初回は相手の現タイトルで生成される")

        # B の下側の表示名を手で書き換える
        b_path = root / "20250111.md"
        b_text = b_path.read_text(encoding="utf-8")
        b_path.write_text(b_text.replace("[A](20250104.md)", "[カスタム表示名](20250104.md)"),
                           encoding="utf-8")
        v2.sync_vault(root)
        _u2, dn2 = regions(b_path.read_text(encoding="utf-8"))
        check("論点:\n[カスタム表示名](20250104.md)" in dn2,
              "sync をもう一度走らせても、手で付けた表示名が相手の現タイトルへ戻らない")


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
