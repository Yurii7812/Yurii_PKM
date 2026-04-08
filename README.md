# Yurii_PKM

Vim 上で Markdown ノートを運用するための PKM（Personal Knowledge Management）プラグインです。

## インストール

### vim-plug

`~/.vimrc`（または `init.vim`）に以下を書いてください。

```vim
Plug 'Yurii7812/Yurii_PKM'
```

その後、Vim で `:PlugInstall` を実行します。

## 初期設定

最低限、ノートを置くルートディレクトリを指定してください。

```vim
let g:yurii_pkm_root = expand('~/memo')
```

必要なら自動同期を無効化できます。

```vim
let g:yurii_pkm_autosync = 0
```

## 使い方（基本）

1. `:YuriiIndex` で `index.md` を開く。
2. ノート上で `nf` / `nn` / `nk` などを使って新規ノートを作成する。
3. `<Tab>` / `<S-Tab>` でリンク移動し、`<Enter>` でリンク先を開く。
4. `nt` でタイトル変更、`bc` や `at` でリンク操作を行う。

## よく使うコマンド

- `:UpdateMD [path]` : ルート配下のリンクタイトルを一括更新
- `:UpdateAll [path]` : `UpdateMD` と同等
- `:SE` : S ノートを A ノートへ展開
- `:RP` : プレフィクス変更と関連リンク更新

## 詳細ドキュメント

キーマップ・全コマンド・テーブル操作などの詳細は以下を参照してください。

- `plugin/yurii_PKM/README.txt`
