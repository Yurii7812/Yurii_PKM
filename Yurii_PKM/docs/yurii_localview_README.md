# yurii_localview

`yurii_localview` is a Vim plugin that keeps editing and navigation inside Vim, while showing a **separate Python graph window** for your notes.

## What it does

- Uses the **currently open file in Vim** as the current node.
- Opens a separate **matplotlib/networkx graph window**.
- Supports both:
  - **local network** (current note + nearby notes)
  - **global network** (all notes under the notes root)
- Uses YAML `title:` as the node label when available.
- Keeps Vim in place. The graph window updates from Vim state.

## Requirements

- Vim with `+python3`
- Python 3
- Python packages:
  - `matplotlib`
  - `networkx`
- A GUI-capable Python/matplotlib environment (`TkAgg` backend is used)

## Folder layout

```text
plugin/yurii_localview.vim
autoload/yurii_localview.vim
python/yurii_localview.py
```

## Commands

```vim
:YuriiLocalViewOpen      " open viewer in local mode
:YuriiLocalViewGlobal    " open viewer in global mode
:YuriiLocalViewLocal     " switch running viewer to local mode
:YuriiLocalViewGlobalRefresh
:YuriiLocalViewLocalRefresh
:YuriiLocalViewSync      " sync current Vim file to viewer
:YuriiLocalViewStop      " stop viewer process
:YuriiLocalViewStatus    " show status
```

## Recommended settings

```vim
let g:yurii_localview_notes_root = '~/notes'
let g:yurii_localview_extensions = ['.md', '.markdown', '.txt']
let g:yurii_localview_use_first_heading_as_title = 1
let g:yurii_localview_local_depth = 2
let g:yurii_localview_label_limit = 40
let g:yurii_localview_auto_sync = 1
```

If `g:yurii_localview_notes_root` is empty, the plugin uses the current working directory when possible, otherwise the current file's directory.

## Vim-side usage

Open the viewer:

```vim
:YuriiLocalViewOpen
```

Switch the graph to global mode:

```vim
:YuriiLocalViewGlobal
```

Move to another note in Vim and sync manually if needed:

```vim
:YuriiLocalViewSync
```

With `let g:yurii_localview_auto_sync = 1`, the graph is also updated on `BufEnter` and `BufWritePost` while the viewer is running.

## Graph window keys

Inside the Python graph window:

- `l` → local mode
- `g` → global mode
- `r` → redraw
- `q` → close window
- mouse click → inspect a node in the info area

## Notes format

`branch` and `back` can be written like:

```md
Branch
[A_260321184428](A_260321184428.md)  やることリスト
[K_260321203904](K_260321203904.md)  スピ-やりること

Back
[index](index.md)  index
```

or with inline relations:

```md
branch: [[note-a]], [[note-b]]
back: [[index]]
```

or with bare titles/paths in a relation section.

## Logs and state

State and process files are stored under:

```text
~/.cache/yurii_localview/
```

Files:

- `state.json`
- `viewer.pid`
- `viewer.log`

If the viewer does not open, check `viewer.log`.
