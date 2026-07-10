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


def test_update_one_does_not_create_parent_section_when_missing(tmp_path: Path) -> None:
    root = tmp_path
    parent = root / "A.md"
    child = root / "sub" / "B.md"
    write_note(parent, "A", child="[B](sub/B.md)\n")
    child.parent.mkdir(parents=True, exist_ok=True)
    child.write_text("# B\n\n本文だけ\n", encoding="utf-8")

    assert update_one(parent, root) == "yurii_PKM: no changes"

    child_text = child.read_text(encoding="utf-8")
    assert "Parent:" not in child_text
    assert "Child:" not in child_text


def test_update_one_does_not_create_child_section_when_missing(tmp_path: Path) -> None:
    root = tmp_path
    parent = root / "A.md"
    child = root / "sub" / "B.md"
    parent.write_text("# A\n\n本文だけ\n", encoding="utf-8")
    write_note(child, "B", parent="[A](../A.md)\n")

    assert update_one(child, root) == "yurii_PKM: no changes"

    parent_text = parent.read_text(encoding="utf-8")
    assert "Child:" not in parent_text
    assert "Parent:" not in parent_text


def test_update_one_does_not_write_parent_to_index(tmp_path: Path) -> None:
    root = tmp_path
    note = root / "A.md"
    index = root / "index.md"
    write_note(note, "A", child="[Index](index.md)\n")
    write_note(index, "Index")

    assert update_one(note, root) == "yurii_PKM: no changes"

    index_text = index.read_text(encoding="utf-8")
    assert "[A](A.md)" not in index_text
    assert "Parent:\nChild:" in index_text
