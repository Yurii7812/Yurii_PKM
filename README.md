# Yurii_PKM

vim初心者でも、**vimrcを自分で書かずに**導入できるように、
かんたんセットアップスクリプトを用意しています。

## 1) まずは Vim / Git を入れる

### Ubuntu / Debian
```bash
sudo apt update
sudo apt install -y vim git curl
```

### Fedora
```bash
sudo dnf install -y vim git curl
```

### macOS (Homebrew)
```bash
brew install vim git curl
```

---

## 2) かんたんセットアップ（コピペ1回）

```bash
git clone https://github.com/Yurii7812/Yurii_PKM.git ~/.vim_yurii_PKM_test
bash ~/.vim_yurii_PKM_test/scripts/install_yurii_pkm_easy.sh
```

このスクリプトが自動で実施します。

- `~/.vimrc_yurii_PKM_test` を作成（このリポジトリの設定をコピー）
- `~/.vimrc` から `source ~/.vimrc_yurii_PKM_test` を読み込む設定
- `vim-plug` のインストール
- `:PlugInstall` 実行

---

## 3) 使い方

```bash
vim
```

または明示的に:

```bash
vim -u ~/.vimrc_yurii_PKM_test
```

---

## 手動で設定ファイルだけ使いたい場合

リポジトリ内の `vimrc_yurii_PKM_test.vim` をそのまま使えます。

```bash
vim -u /path/to/vimrc_yurii_PKM_test.vim
```
