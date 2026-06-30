from pathlib import Path

from yurii_pkm_sync import update_one


def write_note(path: Path, title: str, parent: str = "", child: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f"# {title}\n\nParent:\n{parent}Child:\n{child}BackLink:\n",
        encoding="utf-8",
    )


def test_update_one_syncs_child_links_across_subdirectories(tmp_path: Path) -> None:
    root = tmp_path
    parent = root / "A.md"
    child = root / "sub" / "B.md"
    write_note(parent, "A", child="[B](sub/B.md)\n")
    write_note(child, "B")

    assert update_one(parent, root) == "yurii_PKM: updated reciprocal:1"

    assert "[A](../A.md)" in child.read_text(encoding="utf-8")


def test_update_one_prunes_parent_when_child_link_is_deleted(tmp_path: Path) -> None:
    root = tmp_path
    parent = root / "A.md"
    child = root / "sub" / "B.md"
    write_note(parent, "A", child="[B](sub/B.md)\n")
    write_note(child, "B", parent="[A](../A.md)\n")

    parent.write_text(parent.read_text(encoding="utf-8").replace("[B](sub/B.md)\n", ""), encoding="utf-8")

    assert update_one(parent, root) == "yurii_PKM: updated pruned:1"

    assert "[A](../A.md)" not in child.read_text(encoding="utf-8")


def test_update_one_prunes_child_when_parent_link_is_deleted(tmp_path: Path) -> None:
    root = tmp_path
    parent = root / "A.md"
    child = root / "sub" / "B.md"
    write_note(parent, "A", child="[B](sub/B.md)\n")
    write_note(child, "B", parent="[A](../A.md)\n")

    child.write_text(child.read_text(encoding="utf-8").replace("[A](../A.md)\n", ""), encoding="utf-8")

    assert update_one(child, root) == "yurii_PKM: updated pruned:1"

    assert "[B](sub/B.md)" not in parent.read_text(encoding="utf-8")
