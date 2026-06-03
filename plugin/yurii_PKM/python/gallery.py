#!/usr/bin/env python3
"""Local thumbnail gallery for images linked from a Markdown note.

The Vim plugin calls this script with ``--open NOTE.md``.  The script starts a
small localhost-only HTTP server when needed, opens the browser, then exits.
The long-running server is dependency-free (stdlib only) and serves two things:

* /gallery?file=/abs/note.md  - thumbnail grid + lightbox UI
* /image?file=/abs/image.jpg  - image bytes referenced by the note
"""
from __future__ import annotations

import argparse
import html
import json
import mimetypes
import os
import re
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Iterable

HOST = "127.0.0.1"
DEFAULT_PORT = 8765
GALLERY_PROTOCOL_VERSION = "2"
IMAGE_EXTENSIONS = {".avif", ".bmp", ".gif", ".jpeg", ".jpg", ".png", ".svg", ".webp"}
MARKDOWN_IMAGE_RE = re.compile(r"!\[([^\]]*)\]\(([^)]+)\)")
HTML_IMAGE_RE = re.compile(r"<img\b[^>]*\bsrc=[\"']([^\"']+)[\"'][^>]*>", re.IGNORECASE)
MARKDOWN_LINK_RE = re.compile(r"\[([^\]]+)\]\((https?://[^)]+)\)")
URL_RE = re.compile(r"https?://[^\s<>)\"]+")


def normalize_port(port: int | str | None) -> int:
    try:
        value = int(port or DEFAULT_PORT)
    except (TypeError, ValueError):
        return DEFAULT_PORT
    return value if 1 <= value <= 65535 else DEFAULT_PORT


def server_health(port: int) -> str | None:
    try:
        with urllib.request.urlopen(f"http://{HOST}:{port}/health", timeout=0.4) as response:
            if response.status != 200:
                return None
            return response.read().decode("utf-8", errors="replace")
    except Exception:
        return None


def is_compatible_server_running(port: int) -> bool:
    health = server_health(port)
    return health is not None and f"gallery_protocol={GALLERY_PROTOCOL_VERSION}" in health


def is_port_occupied(port: int) -> bool:
    try:
        with socket.create_connection((HOST, port), timeout=0.2):
            return True
    except OSError:
        return False


def wait_for_server(port: int, timeout: float = 3.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if is_compatible_server_running(port):
            return True
        time.sleep(0.05)
    return False


def strip_wrapping(raw_url: str) -> str:
    value = raw_url.strip()
    if value.startswith("<") and value.endswith(">"):
        value = value[1:-1].strip()
    if "#" in value:
        value = value.split("#", 1)[0]
    return value


def is_remote_url(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    return parsed.scheme in {"http", "https", "data"}


def markdown_url_to_path(note_path: Path, raw_url: str) -> Path | None:
    value = strip_wrapping(raw_url)
    if not value or is_remote_url(value):
        return None
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme and parsed.scheme != "file":
        return None
    path_text = urllib.parse.unquote(parsed.path or value)
    path = Path(path_text)
    if not path.is_absolute():
        path = note_path.parent / path
    return path.resolve()


def iter_line_images(line: str) -> Iterable[tuple[int, str, str]]:
    matches: list[tuple[int, str, str]] = []
    for match in MARKDOWN_IMAGE_RE.finditer(line):
        alt, raw_url = match.groups()
        matches.append((match.start(), alt.strip(), raw_url))
    for match in HTML_IMAGE_RE.finditer(line):
        raw_url = match.group(1)
        matches.append((match.start(), "", raw_url))
    for _, alt, raw_url in sorted(matches, key=lambda item: item[0]):
        yield _, alt, raw_url


def context_from_lines(lines: list[str]) -> tuple[str, list[dict[str, str]]]:
    description_lines: list[str] = []
    links: list[dict[str, str]] = []

    for line in lines:
        text = line.strip()
        if not text:
            continue

        consumed_spans: list[tuple[int, int]] = []
        for match in MARKDOWN_LINK_RE.finditer(text):
            label, href = match.groups()
            links.append({"href": href, "label": label.strip() or href})
            consumed_spans.append(match.span())

        masked = list(text)
        for start, end in consumed_spans:
            for index in range(start, end):
                masked[index] = " "
        remaining = "".join(masked)

        for match in URL_RE.finditer(remaining):
            href = match.group(0)
            links.append({"href": href, "label": href})

        remaining = URL_RE.sub(" ", remaining)
        remaining = re.sub(r"\s+", " ", remaining).strip()
        if remaining:
            description_lines.append(remaining)

    return "\n".join(description_lines).strip(), links


def iter_markdown_images(note_path: Path, text: str) -> Iterable[dict[str, object]]:
    seen: set[Path] = set()
    block_lines: list[str] = []

    for line in text.splitlines():
        if not line.strip():
            block_lines = []
            continue

        images = list(iter_line_images(line))
        if not images:
            block_lines.append(line.strip())
            continue

        description, links = context_from_lines(block_lines)
        for _, alt, raw_url in images:
            image_path = markdown_url_to_path(note_path, raw_url)
            if image_path is None or image_path in seen:
                continue
            if image_path.suffix.lower() not in IMAGE_EXTENSIONS:
                continue
            seen.add(image_path)
            label = description or alt or image_path.name
            yield {
                "path": str(image_path),
                "label": label,
                "description": description,
                "links": links,
            }


def read_gallery(note_file: str) -> tuple[Path, list[dict[str, object]], str | None]:
    note_path = Path(note_file).expanduser().resolve()
    if not note_path.is_file():
        return note_path, [], f"Markdown file not found: {note_path}"
    text = note_path.read_text(encoding="utf-8", errors="replace")
    images = list(iter_markdown_images(note_path, text))
    return note_path, images, None


def image_url(port: int, image_path: str) -> str:
    return f"/image?file={urllib.parse.quote(image_path)}"


def render_gallery(note_file: str, port: int) -> bytes:
    note_path, images, error = read_gallery(note_file)
    title = note_path.stem or "Gallery"
    payload = [
        {
            "src": image_url(port, item["path"]),
            "name": Path(item["path"]).name,
            "path": item["path"],
            "label": item["label"],
            "description": item.get("description", ""),
            "links": item.get("links", []),
        }
        for item in images
    ]
    data = json.dumps(payload, ensure_ascii=False)
    error_html = f'<p class="error">{html.escape(error)}</p>' if error else ""
    empty_html = "" if payload else '<p class="empty">このMarkdownファイルには画像リンクが見つかりませんでした。</p>'
    body = f"""<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} - Yurii PKM Gallery</title>
<style>
:root {{ color-scheme: dark; --bg:#101318; --panel:#181d24; --text:#eef2f8; --muted:#99a3b3; --accent:#6cc6ff; }}
* {{ box-sizing: border-box; }}
body {{ margin:0; font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background:var(--bg); color:var(--text); }}
header {{ position: sticky; top:0; z-index:2; background:rgba(16,19,24,.92); backdrop-filter: blur(10px); border-bottom:1px solid #2a313c; padding:16px 22px; }}
h1 {{ margin:0 0 6px; font-size:22px; }}
.meta {{ color:var(--muted); font-size:13px; overflow-wrap:anywhere; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(160px, 1fr)); gap:14px; padding:20px; }}
.card {{ border:1px solid #29313c; background:var(--panel); border-radius:12px; overflow:hidden; cursor:pointer; transition:transform .12s ease, border-color .12s ease; }}
.card:hover {{ transform:translateY(-2px); border-color:var(--accent); }}
.thumb {{ width:100%; aspect-ratio:1/1; object-fit:cover; display:block; background:#0b0d11; }}
.caption {{ padding:9px 10px 11px; font-size:12px; color:var(--muted); overflow:hidden; }}
.caption-title {{ color:#dce6f3; line-height:1.35; display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }}
.caption-links {{ margin-top:6px; display:flex; flex-direction:column; gap:3px; }}
.source-link {{ color:var(--accent); text-decoration:none; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }}
.source-link:hover {{ text-decoration:underline; }}
.empty, .error {{ margin:20px; padding:14px 16px; border-radius:10px; background:#1b2028; color:var(--muted); }}
.error {{ color:#ffb4b4; }}
.lightbox {{ position:fixed; inset:0; display:none; align-items:center; justify-content:center; background:rgba(0,0,0,.9); z-index:10; }}
.lightbox.open {{ display:flex; }}
.stage {{ width:100vw; height:100vh; display:flex; align-items:center; justify-content:center; padding:58px 68px 70px; }}
.stage img {{ max-width:100%; max-height:100%; object-fit:contain; box-shadow:0 12px 40px rgba(0,0,0,.45); }}
.lb-info {{ position:fixed; left:18px; right:18px; bottom:16px; text-align:center; color:#dce6f3; font-size:14px; overflow-wrap:anywhere; }}
.lb-title {{ font-weight:600; margin-bottom:5px; white-space:pre-wrap; }}
.lb-links {{ display:flex; justify-content:center; gap:10px; flex-wrap:wrap; }}
button {{ position:fixed; border:0; color:white; background:rgba(255,255,255,.12); border-radius:999px; cursor:pointer; }}
button:hover {{ background:rgba(255,255,255,.2); }}
.close {{ top:14px; right:14px; width:42px; height:42px; font-size:28px; line-height:42px; }}
.nav {{ top:50%; transform:translateY(-50%); width:52px; height:72px; font-size:42px; }}
.prev {{ left:12px; }} .next {{ right:12px; }}
.help {{ position:fixed; top:22px; left:20px; color:var(--muted); font-size:13px; }}
</style>
</head>
<body>
<header><h1>{html.escape(title)}</h1><div class="meta">分類: {html.escape(note_path.name)} / {len(payload)} images / ← → で移動、Escで閉じる</div><div class="meta">{html.escape(str(note_path))}</div></header>
{error_html}{empty_html}
<main id="grid" class="grid"></main>
<div id="lightbox" class="lightbox" aria-hidden="true">
  <div class="help">← →: 前後 / Esc: 閉じる</div>
  <button class="close" id="close" title="閉じる">×</button>
  <button class="nav prev" id="prev" title="前へ">‹</button>
  <div class="stage"><img id="full" alt=""></div>
  <button class="nav next" id="next" title="次へ">›</button>
  <div class="lb-info" id="info"></div>
</div>
<script>
const images = {data};
const grid = document.getElementById('grid');
const lightbox = document.getElementById('lightbox');
const full = document.getElementById('full');
const info = document.getElementById('info');
let current = 0;
function linkText(link) {{
  try {{
    const url = new URL(link.href);
    return link.label === link.href ? url.hostname + url.pathname : link.label;
  }} catch (_) {{
    return link.label || link.href;
  }}
}}
function addLinks(container, links) {{
  if (!links || !links.length) return;
  const linksBox = document.createElement('div');
  linksBox.className = container === info ? 'lb-links' : 'caption-links';
  links.forEach((link) => {{
    const anchor = document.createElement('a');
    anchor.className = 'source-link';
    anchor.href = link.href;
    anchor.target = '_blank';
    anchor.rel = 'noopener noreferrer';
    anchor.textContent = linkText(link);
    anchor.title = link.href;
    anchor.addEventListener('click', (event) => event.stopPropagation());
    linksBox.appendChild(anchor);
  }});
  container.appendChild(linksBox);
}}
function fillInfo(item) {{
  info.replaceChildren();
  const title = document.createElement('div');
  title.className = 'lb-title';
  title.textContent = `${{current + 1}} / ${{images.length}} — ${{item.description || item.label}}`;
  info.appendChild(title);
  addLinks(info, item.links);
  const path = document.createElement('div');
  path.className = 'meta';
  path.textContent = item.path;
  info.appendChild(path);
}}
function openAt(index) {{ if (!images.length) return; current = (index + images.length) % images.length; const item = images[current]; full.src = item.src; full.alt = item.label; fillInfo(item); lightbox.classList.add('open'); lightbox.setAttribute('aria-hidden', 'false'); }}
function closeBox() {{ lightbox.classList.remove('open'); lightbox.setAttribute('aria-hidden', 'true'); full.removeAttribute('src'); }}
function move(delta) {{ openAt(current + delta); }}
images.forEach((item, index) => {{
  const card = document.createElement('article');
  card.className = 'card';
  card.title = item.path;
  const img = document.createElement('img');
  img.className = 'thumb';
  img.loading = 'lazy';
  img.src = item.src;
  img.alt = item.label;
  const caption = document.createElement('div');
  caption.className = 'caption';
  const captionTitle = document.createElement('div');
  captionTitle.className = 'caption-title';
  captionTitle.textContent = item.description || item.label;
  caption.appendChild(captionTitle);
  addLinks(caption, item.links);
  card.append(img, caption);
  card.addEventListener('click', () => openAt(index));
  grid.appendChild(card);
}});
document.getElementById('close').addEventListener('click', closeBox);
document.getElementById('prev').addEventListener('click', () => move(-1));
document.getElementById('next').addEventListener('click', () => move(1));
lightbox.addEventListener('click', (event) => {{ if (event.target === lightbox) closeBox(); }});
document.addEventListener('keydown', (event) => {{ if (!lightbox.classList.contains('open')) return; if (event.key === 'Escape') closeBox(); if (event.key === 'ArrowLeft') move(-1); if (event.key === 'ArrowRight') move(1); }});
</script>
</body>
</html>"""
    return body.encode("utf-8")


class GalleryHandler(BaseHTTPRequestHandler):
    server_version = "YuriiPKMGallery/1.0"

    def log_message(self, format: str, *args: object) -> None:
        return

    def send_bytes(self, status: int, content: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        if parsed.path == "/health":
            self.send_bytes(200, f"ok gallery_protocol={GALLERY_PROTOCOL_VERSION}".encode("utf-8"), "text/plain; charset=utf-8")
            return
        if parsed.path == "/gallery":
            note_file = query.get("file", [""])[0]
            self.send_bytes(200, render_gallery(note_file, self.server.server_port), "text/html; charset=utf-8")
            return
        if parsed.path == "/image":
            image_file = query.get("file", [""])[0]
            path = Path(image_file).expanduser().resolve()
            if not path.is_file() or path.suffix.lower() not in IMAGE_EXTENSIONS:
                self.send_bytes(404, b"not found", "text/plain; charset=utf-8")
                return
            content_type = mimetypes.guess_type(str(path))[0] or "application/octet-stream"
            self.send_bytes(200, path.read_bytes(), content_type)
            return
        self.send_bytes(404, b"not found", "text/plain; charset=utf-8")


def serve(port: int) -> None:
    server = ThreadingHTTPServer((HOST, port), GalleryHandler)
    server.serve_forever()


def choose_gallery_port(preferred_port: int) -> int | None:
    for port in range(preferred_port, min(preferred_port + 20, 65536)):
        if is_compatible_server_running(port):
            return port
        if not is_port_occupied(port):
            return port
    return None


def start_server(port: int) -> None:
    script = Path(__file__).resolve()
    subprocess.Popen(
        [sys.executable, str(script), "--serve", "--port", str(port)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def open_gallery(note_file: str, port: int) -> int:
    selected_port = choose_gallery_port(port)
    if selected_port is None:
        print(f"No available gallery port near {HOST}:{port}", file=sys.stderr)
        return 1
    if not is_compatible_server_running(selected_port):
        start_server(selected_port)
        if not wait_for_server(selected_port):
            print(f"Failed to start gallery server on {HOST}:{selected_port}", file=sys.stderr)
            return 1
    note_path = Path(note_file).expanduser().resolve()
    url = f"http://{HOST}:{selected_port}/gallery?file={urllib.parse.quote(str(note_path))}&v={GALLERY_PROTOCOL_VERSION}"
    webbrowser.open(url)
    print(url)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Yurii PKM Markdown image gallery")
    parser.add_argument("--port", type=int, default=int(os.environ.get("YURII_PKM_GALLERY_PORT", DEFAULT_PORT)))
    parser.add_argument("--serve", action="store_true", help="run the localhost gallery server")
    parser.add_argument("--open", metavar="NOTE.md", help="start server if needed and open NOTE.md gallery")
    args = parser.parse_args(argv)
    port = normalize_port(args.port)
    if args.serve:
        serve(port)
        return 0
    if args.open:
        return open_gallery(args.open, port)
    parser.error("use --open NOTE.md or --serve")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
