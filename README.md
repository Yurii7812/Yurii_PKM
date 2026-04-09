# Yurii_PKM

Vim/Neovim 上で Markdown ベースのノートを管理するための PKM（Personal Knowledge Management）プラグインです。  
ノート作成・リンク移動・タイトル同期・表編集までを 1 つのワークフローで扱えます。

---
Vim 上で Markdown ノートを運用するための PKM（Personal Knowledge Management）プラグインです。

## インストール

### vim-plug

`~/.vimrc`（または `init.vim`）に以下を書いてください。

```vim
Plug 'Yurii7812/Yurii_PKM'
```

その後、Vim/Neovim で以下を実行します。

```vim
:PlugInstall
```

---

## 必須設定（最小）

ノートを保存するルートディレクトリを指定します。

```vim
let g:yurii_pkm_root = expand('~/memo')
```

---

## 使い方（最短）

1. `:YuriiIndex` で `index.md` を開く。
2. `nf` / `nn` / `nk` で新規ノートを作成する。
3. `<Tab>` / `<S-Tab>` でリンク移動、`<Enter>` でリンクを開く。
4. `nt` でタイトル編集、`bc` / `at` でリンク操作を行う。

---

## 推奨設定

```vim
" 保存時 AutoSync（既定: 1）
let g:yurii_pkm_autosync = 1

" コマンド実行前に自動保存（既定: 1）
let g:yurii_pkm_auto_save_on_command = 1

" 履歴件数（既定: 200）
let g:yurii_pkm_history_max = 200

" 新規ノートの既定プレフィクス
let g:yurii_pkm_default_child_prefix = 'C'
let g:yurii_pkm_default_quick_prefix = 'F'
let g:yurii_pkm_default_atomic_prefix = 'C'
```

---

## 機能一覧（整理版）

### 1) ノート作成

- `nf` : クイックノート作成（タイトルなし）
- `nn` : プレフィクスなしの新規ノート作成（YAML `filetype: N`）
- `nk` : プレフィクスなしの新規ノート作成（YAML `filetype: K`）
- `na` / `:NA` : 現在位置に A ノート作成
- `:NF` : 引数付きクイック作成
- ビジュアルモードでも `nf` / `nn` / `nk` に対応

### 2) リンク移動・履歴

- `<Tab>` : 次のリンクへ移動
- `<S-Tab>` : 前のリンクへ移動
- `<Enter>` : カーソル下リンクを開く
- `<BS>` : 履歴を戻る

### 3) タイトル変更

- `nt` : 空入力からタイトル編集
- `nT` / `:NT` : 現在タイトルを残して編集
- タイトル変更時は、同一ターゲットへのリンクのうち「旧タイトルと一致する表示テキスト」だけ新タイトルへ更新（例: `[A](x.md)` は更新、`[aaa](x.md)` は維持）

### 4) リンク操作

- `bc` / `:BC` : クリップボードのファイルを Branch に追加
- `at` / `:AT` : クリップボード側ノートへ逆リンク追加
- `yn` / `:YN` : 現在ファイル名をヤンク
- `\l` / `:Linkify` : ファイル名テキストを Markdown リンク化
- Visual `\l` / `:LinkifySelection` : 選択文字列をクリップボードのターゲットへリンク化（`pkm:fixed-text` マーカー付きでタイトル同期の自動上書きを抑止）
- `\L` / `:LinkFixedToggle` : カーソル下リンクの固定マーカー（`pkm:fixed-text`）を ON/OFF
- `\p` / `:PasteLink` : クリップボードのリンクを挿入
- `p` : `"+p` へマップ（システムクリップボード貼り付け）
- `gp` : 旧挙動の貼り付け

### 5) 同期・一括更新

- `:UpdateMD [path]` : リンクタイトル等の一括更新
- `:UpdateAll [path]` / `:UpdateALL [path]` : 同等コマンド
- Back セクションは、該当リンクがあるときだけ `category:`（K系）/`note:`（N系）見出しを自動表示

- `.md` 保存時に AutoSync（`g:yurii_pkm_autosync=1` 時）

### 6) 変換・リネーム

- `\se` / `:SE` : S ノートを展開して関連ファイルを開く
- `mp` / `:RP` : YAML の `filetype` を変更

### 7) インデックス・ユーティリティ

- `:YuriiIndex` : `index.md` を開く
- `:YuriiChooseIndexDir` : index ルート選択
- `:SortYomi` : Branch の読み順ソート
- `:CheckPrefix` : プレフィクスチェック
- `:OutlineEdit` / `\oe` : アウトライン編集（別バッファで見出し編集、`←/→` で `#` 数変更、`q` / `:write` / `ZZ` / `:OutlineApply` で反映）


### 8) Markdown テーブル編集

- 作成: `:TN`, `:NewTable`, `:YuriiTable`
- 整形: `:TA`
- 行編集: `:TRE`
- CSV編集: `:TCSV`, `:TableCsvEdit`, `:TableCsvApplySaved`
- 変換: `:TableToCsv` (`:TCE`), `:CsvToTable`
- 新規CSVテーブル: `:TableCsvNew`, `:TCN`
- 行列操作: `:TAR`, `:TAC`, `:TDR`, `:TDC`
- ノーマルモード補助:
  - `\tn`, `\ta`, `\te`, `\tc`, `\tt`, `\tnc`, `\tar`, `\tac`, `\tdr`, `\tdc`
- テーブル内挿入モード補助:
  - `<Tab>` / `<S-Tab>` / `<CR>` がテーブル操作として動作

---

## 主要コマンド一覧（早見表）

| 種別 | コマンド |
|---|---|
| 作成 | `:NF`, `:NA`, `:CA` |
| 更新 | `:UpdateMD`, `:UpdateAll`, `:UpdateALL` |
| 編集 | `:NT`, `:RP`, `:OutlineEdit` |
| 移動 | `:YuriiIndex`, `:YuriiChooseIndexDir` |
| 変換 | `:SE`, `:SortYomi`, `:Linkify`, `:LinkifySelection`, `:PasteLink` |
| テーブル | `:TN`, `:TA`, `:TRE`, `:TCSV`, `:TableToCsv`, `:CsvToTable`, `:TAR`, `:TAC`, `:TDR`, `:TDC` |

---

## 既定値つき設定変数

| 変数 | 既定値 | 内容 |
|---|---:|---|
| `g:yurii_pkm_root` | `''` | PKM ルートディレクトリ |
| `g:yurii_pkm_default_child_prefix` | `'C'` | 子ノート既定プレフィクス |
| `g:yurii_pkm_default_quick_prefix` | `'F'` | クイック作成既定プレフィクス |
| `g:yurii_pkm_default_atomic_prefix` | `'C'` | Atomic 作成既定プレフィクス |
| `g:yurii_pkm_history_max` | `200` | 履歴最大件数 |
| `g:yurii_pkm_autosync` | `1` | 保存時 AutoSync 有効/無効 |
| `g:yurii_pkm_auto_save_on_command` | `1` | コマンド前自動保存 |
| `g:yurii_pkm_python` | `{plugin}/python/yurii_pkm_sync.py` | 同期スクリプト |
| `g:yurii_pkm_expand_s_python` | `{plugin}/python/expand_s.py` | S展開スクリプト |

---


## トラブルシューティング（マージ競合エラー）

README に以下のような文字列が見える場合は、Git のマージ競合が未解決です。

- `<<<<<<<`
- `=======`
- `>>>>>>>`

このリポジトリの `README.md` は競合解消済みの状態が正です。  
競合マーカーが残っている場合は、競合行を削除して 1 つの内容に統合してからコミットしてください。

---

## 参考

- 詳細な操作リファレンス: `plugin/yurii_PKM/README.txt`
