# Yurii_PKM

公開用の統合版です。`vim-plug` でこのリポジトリを 1 行追加するだけで、`Yurii_PKM` 本体に加えて次も同時に入ります。

- `yurii_PKM`
- `yurii_search`
- `yurii_localview`
- `kalisi` colorscheme（同梱）

## 最小 vimrc

```vim
call plug#begin(g:plug_home)
  Plug 'https://github.com/Yurii7812/Yurii_PKM.git', { 'rtp': 'Yurii_PKM' }
call plug#end()

set background=light
colorscheme kalisi
```

これだけでも動くように、プラグイン側で最低限の `filetype plugin indent on` と `syntax enable` を行うようにしてあります。

## ルートディレクトリを固定したい場合

初回起動時に選ばせてもよいですが、固定したいなら vimrc にこれを足します。

```vim
let g:yurii_pkm_root = '~/Desktop/yurii_note'
```

## リポジトリ構成

```text
Yurii_PKM/
  plugin/
  autoload/
  python/
  colors/
```

この構成なので、以下の指定でそのまま動きます。

```vim
Plug 'https://github.com/Yurii7812/Yurii_PKM.git', { 'rtp': 'Yurii_PKM' }
```

## 補足

- `kalisi` は同梱してあるので、別途色テーマを追加で `Plug` しなくて大丈夫です。
- `yurii_localview` は外部 Python 実行です。`python3` があれば動きます。
- `yurii_search` も `python3` を優先し、なければ `python` を使います。
