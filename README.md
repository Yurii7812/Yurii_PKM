# yurii_PKM

`yurii_PKM` は、あなたの PKM（Personal Knowledge Management）運用向けに作られた Vim プラグイン集を、
**1つの Vim プラグインとして統合**したリポジトリです。

この統合により、以下を一括で提供します。

- 既存の PKM 本体機能（`yurii_PKM/`）
- ファイル検索 UI（`yurii_search/`）
- 以前は単体 `.vim` ファイルだった補助コマンド群
  - `:FileContentSearch`
  - `:Rename`
  - `:SetImageSize`
  - `:Autocwindow`

## Vim-Plug での導入

```vim
call plug#begin('~/.vim/plugged')
  Plug 'YOUR_GITHUB_ID/Yurii_PKM'
call plug#end()
```

その後、Vim で以下を実行:

```vim
:PlugInstall
```

> `YOUR_GITHUB_ID/Yurii_PKM` は、実際の GitHub リポジトリパスに置き換えてください。

## 使い方

導入後は通常通りコマンドを実行できます。

- PKM 本体コマンド（例: `:UpdateAll`, `:YuriiIndex`）
- 検索コマンド（` :FSearch`）
- 統合補助コマンド（` :FileContentSearch`, `:Rename`, `:SetImageSize`, `:Autocwindow`）

詳細な操作は `yurii_PKM/README.txt` を参照してください。
