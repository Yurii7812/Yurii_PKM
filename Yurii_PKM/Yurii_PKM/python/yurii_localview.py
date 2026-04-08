# yurii_localview.py (FULL VERSION with font fix)

import os
import re
import json

import matplotlib
matplotlib.use('TkAgg')

import matplotlib.pyplot as plt
import matplotlib as mpl
import networkx as nx

# ===== Font Fix =====
mpl.rcParams['font.family'] = 'sans-serif'
mpl.rcParams['font.sans-serif'] = [
    'Noto Sans CJK JP',
    'IPAexGothic',
    'IPAGothic',
    'Yu Gothic',
    'TakaoGothic',
    'DejaVu Sans',
]
mpl.rcParams['font.size'] = 14
mpl.rcParams['axes.unicode_minus'] = False

# ===== Utils =====
def read_file(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return f.read()
    except:
        return ""

def extract_title(content, fallback):
    m = re.search(r'^title:\s*(.+)$', content, re.MULTILINE)
    if m:
        return m.group(1).strip()
    return fallback

def extract_links(content, key):
    lines = content.splitlines()
    results = []
    mode = False
    for line in lines:
        if line.strip().lower() == key.lower():
            mode = True
            continue
        if mode:
            if not line.strip():
                continue
            m = re.findall(r'\(([^)]+)\)', line)
            for x in m:
                results.append(x.replace('.md',''))
    return results

# ===== Graph Build =====
def build_graph(root):
    G = nx.Graph()
    files = []
    for dirpath, _, filenames in os.walk(root):
        for f in filenames:
            if f.endswith('.md'):
                files.append(os.path.join(dirpath, f))

    for f in files:
        content = read_file(f)
        name = os.path.splitext(os.path.basename(f))[0]
        title = extract_title(content, name)

        G.add_node(name, title=title)

        branches = extract_links(content, 'Branch')
        backs = extract_links(content, 'Back')

        for b in branches:
            G.add_edge(name, b)

        for b in backs:
            G.add_edge(name, b)

    return G

# ===== Draw =====
def draw_graph(G, current=None):
    plt.clf()

    pos = nx.spring_layout(G, iterations=10)

    labels = {n: G.nodes[n].get('title', n) for n in G.nodes}

    nx.draw(
        G,
        pos,
        labels=labels,
        with_labels=True,
        node_size=800,
        font_size=12
    )

    if current and current in G:
        nx.draw_networkx_nodes(
            G,
            pos,
            nodelist=[current],
            node_color='red',
            node_size=1200
        )

    plt.title("yurii_localview")
    plt.pause(0.1)

# ===== Main =====
def main():
    root = os.path.expanduser(os.environ.get("YURII_NOTES_ROOT", "."))
    current = os.environ.get("YURII_CURRENT_FILE", "")

    G = build_graph(root)

    plt.ion()
    draw_graph(G, current)

    print("Press q to quit")

    while True:
        try:
            cmd = input()
            if cmd.strip() == 'q':
                break
        except:
            break

if __name__ == "__main__":
    main()
