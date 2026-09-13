#!/usr/bin/env python3
"""expand_v2 の自己完結テスト（pytest 非依存）。

    python3 test_expand_v2.py
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import expand_v2 as ex
import note_format_v2 as v2

_FAILED: list[str] = []


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FAIL {msg}")
        _FAILED.append(msg)


UP_MARK = v2.UP_MARK
DOWN_MARK = v2.DOWN_MARK


def note(path: Path, title: str, body: str = "", up: str = "", down: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    txt = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n"
    if body:
        txt += body.strip("\n") + "\n\n"
    txt += f"{UP_MARK}\n"
    if up:
        txt += up.strip("\n") + "\n"
    txt += DOWN_MARK + "\n"
    if down:
        txt += down.strip("\n") + "\n"
    path.write_text(txt, encoding="utf-8")


def _fixture(root: Path) -> None:
    """G(グループ) <-索引- A -資料-> C ; A の本文が B を素のリンクで言及。"""
    note(root / "G.md", "G", up="", down="索引:\n[A](A.md)")
    note(root / "A.md", "A", body="Aの本文。参照: [B](B.md)",
         up="グループ:\n[G](G.md)", down="資料:\n[C](C.md)")
    note(root / "B.md", "B")
    note(root / "C.md", "C")
    v2.sync_vault(root)


def test_directions_parent_child_backlink() -> None:
    print("directions: 親/子/文中バックリンクを正しく拾う")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        a = notes[(root / "A.md").resolve()]
        d_a = ex._directions(a, root, by_name, ids)
        a_id = ids[(root / "A.md").resolve()]
        g_id = ids[(root / "G.md").resolve()]
        c_id = ids[(root / "C.md").resolve()]
        b_id = ids[(root / "B.md").resolve()]
        check(d_a["parent"] == {g_id}, "A の親は G")
        check(d_a["child"] == {c_id}, "A の子は C")
        check(d_a["backlink"] == {b_id}, "A の文中は本文で素リンクした B")
        del a_id  # 未使用警告よけ


def test_simple_mode_depth1() -> None:
    print("simple: 深さ1で親・子・文中すべてを平等に1階層集める")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]

        dir_cache: dict = {}
        def dir_of(nid):
            if nid not in dir_cache:
                dir_cache[nid] = ex._directions(notes[id_to_path[nid]], root, by_name, ids)
            return dir_cache[nid]

        order = ex.collect_simple(start_id, dir_of, 1)
        titles = {notes[id_to_path[i]].title for i in order}
        check(titles == {"A", "G", "C", "B"}, "深さ1で親G・子C・文中Bが全部入る")


def test_simple_mode_depth0_only_start() -> None:
    print("simple: 深さ0なら起点だけ")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]
        order = ex.collect_simple(start_id, lambda nid: ex._directions(
            notes[id_to_path[nid]], root, by_name, ids), 0)
        check(order == [start_id], "深さ0は起点ノートのみ")


def test_detailed_mode_independent_budgets() -> None:
    print("detailed: 種類ごとに独立した深さで絞り込める")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]

        def dir_of(nid):
            return ex._directions(notes[id_to_path[nid]], root, by_name, ids)

        order = ex.collect_detailed(start_id, dir_of, child_depth=1, parent_depth=0, backlink_depth=0)
        titles = {notes[id_to_path[i]].title for i in order}
        check(titles == {"A", "C"}, "子だけ許可（親・文中は0）だと A と C だけ")

        order2 = ex.collect_detailed(start_id, dir_of, child_depth=0, parent_depth=1, backlink_depth=0)
        titles2 = {notes[id_to_path[i]].title for i in order2}
        check(titles2 == {"A", "G"}, "親だけ許可だと A と G だけ")

        order3 = ex.collect_detailed(start_id, dir_of, child_depth=0, parent_depth=0, backlink_depth=1)
        titles3 = {notes[id_to_path[i]].title for i in order3}
        check(titles3 == {"A", "B"}, "文中だけ許可だと A と B だけ")


def test_detailed_mode_child_chain_does_not_leak_via_parent() -> None:
    print("detailed: 子は純粋なチェーン。親経由で兄弟が見えても、兄弟の子までは追わない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # G(グループ) の子は A と H。A は深い子チェーン A->C1->C2 を持つ。
        # H は G の子として「覗き」で見えてよいが、H の子 HC までは追わない。
        note(root / "G.md", "G", down="索引:\n[A](A.md)\n[H](H.md)")
        note(root / "A.md", "A", up="グループ:\n[G](G.md)", down="資料:\n[C1](C1.md)")
        note(root / "C1.md", "C1", up="資料:\n[A](A.md)", down="資料:\n[C2](C2.md)")
        note(root / "C2.md", "C2", up="資料:\n[C1](C1.md)")
        note(root / "H.md", "H", up="グループ:\n[G](G.md)", down="資料:\n[HC](HC.md)")
        note(root / "HC.md", "HC", up="資料:\n[H](H.md)")
        v2.sync_vault(root)

        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]

        def dir_of(nid):
            return ex._directions(notes[id_to_path[nid]], root, by_name, ids)

        # 子を深く(3)・親は浅く(1)。子チェーン A->C1->C2 に加えて、親 G と、
        # G を覗いた時に見える兄弟 H は含まれるが、H の子 HC までは追わない
        # （覗きは 1 階層だけで再帰しない）。
        order = ex.collect_detailed(start_id, dir_of, child_depth=3, parent_depth=1, backlink_depth=0)
        titles = {notes[id_to_path[i]].title for i in order}
        check(titles == {"A", "C1", "C2", "G", "H"},
              "親経由で G の子（兄弟 H）までは見えるが、H の子 HC までは追わない")


def test_detailed_mode_peek_is_one_level_non_recursive() -> None:
    print("detailed: 親・文中の経路上では他方向を1階層だけ覗く（そこからは再帰しない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # 文中方向のチェーン: A の本文が X を言及、X の本文が Y を言及。
        # X には子 XC、親 XP がいて「覗き」対象。Y にも子 YC がいるが、
        # 覗きは X までで、Y から先の覗きの、さらにその先までは追わない
        # （＝ Y 自体は backlink_depth=2 のチェーンで含まれるが、YC は
        # 「Y の覗き」で見えてよく、YC のさらに先は追わない、という境界を確認）。
        note(root / "A.md", "A", body="言及: [X](X.md)")
        note(root / "X.md", "X", body="言及: [Y](Y.md)",
             up="資料:\n[XP](XP.md)", down="資料:\n[XC](XC.md)")
        note(root / "Y.md", "Y", down="資料:\n[YC](YC.md)")
        note(root / "XP.md", "XP", down="資料:\n[X](X.md)")
        note(root / "XC.md", "XC", up="資料:\n[X](X.md)")
        note(root / "YC.md", "YC", up="資料:\n[Y](Y.md)")
        v2.sync_vault(root)

        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]

        def dir_of(nid):
            return ex._directions(notes[id_to_path[nid]], root, by_name, ids)

        order = ex.collect_detailed(start_id, dir_of, child_depth=0, parent_depth=0, backlink_depth=2)
        titles = {notes[id_to_path[i]].title for i in order}
        check(titles == {"A", "X", "Y", "XP", "XC", "YC"},
              "文中チェーン A->X->Y の各ノード(X,Y)で子/親を1階層覗く（XP,XC,YC）が、"
              "覗いた先(XC 等)からさらに先へは追わない")


def test_render_strips_own_h1_and_frontmatter() -> None:
    print("render: front matter・見張りコメントは出さず、自分の H1 も二重にしない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 1))
        text = out_path.read_text(encoding="utf-8")
        check("attribute:" not in text, "front matter は含まれない")
        check(UP_MARK not in text and DOWN_MARK not in text, "見張りコメントは含まれない")
        lines = text.split("\n")
        check("# A" not in lines, "本文側の重複 H1 (# A) は除去される（## A だけが残る）")
        check("## A" in text and "## G" in text and "## C" in text and "## B" in text,
              "各ノートが見出しとして出る")
        check("Aの本文。参照:" in text, "本文の中身は保持される")


def test_run_creates_file_under_tmp_dir() -> None:
    print("run: 出力先は ROOT/_tmp/T_<timestamp>.md")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 0))
        check(out_path.parent == root / v2.EXPAND_TMP_DIR, "_tmp ディレクトリの下に作られる")
        check(out_path.name.startswith("T_") and out_path.suffix == ".md",
              "ファイル名は T_ + タイムスタンプ")


def test_tmp_dir_excluded_from_sync_scan() -> None:
    print("sync: _tmp 配下のファイルは vault スキャンから除外される")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 1))
        check(out_path.exists(), "展開ファイル自体は作られている")
        found = [p for p in v2._iter_md(root) if v2.EXPAND_TMP_DIR in p.relative_to(root).parts]
        check(found == [], "_iter_md は _tmp 配下を無視する")


def test_prefs_roundtrip() -> None:
    print("prefs: detailed 実行後に前回設定を記録・復元できる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        check(ex._load_prefs(root) is None, "初回は前回設定なし")
        ex._run(root, root / "A.md",
                lambda sid, dir_of: ex.collect_detailed(sid, dir_of, 2, 1, 0))
        ex._save_prefs(root, 2, 1, 0)
        prefs = ex._load_prefs(root)
        check(prefs == {"child": 2, "parent": 1, "backlink": 0}, "保存した数値がそのまま読み出せる")


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
