# yurii_PKM

`yurii_PKM` は、あなたの PKM（Personal Knowledge Management）運用向けに作られた Vim プラグイン集を、
**`Yurii_PKM/` フォルダ配下に1つへ統合**した構成です。

この統合により、以下を `Yurii_PKM/` 配下で一括提供します。

- PKM 本体機能（`Yurii_PKM/plugin`, `Yurii_PKM/autoload`, `Yurii_PKM/python`）
- ファイル検索 UI（`Yurii_PKM/autoload/yurii_search.vim`, `Yurii_PKM/python/fsearch_tui.py`）
- 以前は単体 `.vim` ファイルだった補助コマンド群
  - `:FileContentSearch`
  - `:Rename`
  - `:SetImageSize`
  - `:Autocwindow`

## Vim-Plug での導入

```vim
call plug#begin('~/.vim/plugged')
  " GitHub URLをそのまま書ける（IDを知らなくても可）
  Plug 'https://github.com/<OWNER>/Yurii_PKM.git', { 'rtp': 'Yurii_PKM' }
call plug#end()
```

その後、Vim で以下を実行:

```vim
:PlugInstall
```

> `<OWNER>` は GitHub のユーザー名または Organization 名です。  
> `Plug 'owner/repo'` 形式でも、`Plug 'https://github.com/owner/repo.git'` 形式でも導入できます。  
> 本リポジトリは `Yurii_PKM/` を runtimepath として使うため、`{ 'rtp': 'Yurii_PKM' }` を指定します。

## 使い方

導入後は通常通りコマンドを実行できます。

- PKM 本体コマンド（例: `:UpdateAll`, `:YuriiIndex`）
- 検索コマンド（` :FSearch`）
- 統合補助コマンド（` :FileContentSearch`, `:Rename`, `:SetImageSize`, `:Autocwindow`）

詳細な操作は `Yurii_PKM/README.txt` を参照してください。

## マージ衝突について

競合を減らすため、個人環境用の `vimrc_yurii_PKM` は削除し、プラグイン本体に集約しました。  
また、`README.md` は `.gitattributes` の `merge=ours` で作業ブランチ側を優先する設定にしています。
