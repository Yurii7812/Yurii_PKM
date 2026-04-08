#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Yurii7812/Yurii_PKM.git"
TARGET_DIR="${HOME}/.vim_yurii_PKM_test"
VIMRC_TARGET="${HOME}/.vimrc_yurii_PKM_test"
MAIN_VIMRC="${HOME}/.vimrc"
PLUG_VIM="${HOME}/.vim/autoload/plug.vim"

info() {
  printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[WARN]\033[0m %s\n' "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

if ! need_cmd git; then
  cat <<'MSG'
[ERROR] git が見つかりません。
先に git をインストールしてください。

- Ubuntu/Debian: sudo apt update && sudo apt install -y git
- Fedora:        sudo dnf install -y git
- macOS:         brew install git
MSG
  exit 1
fi

if ! need_cmd vim; then
  cat <<'MSG'
[ERROR] vim が見つかりません。
先に vim をインストールしてください。

- Ubuntu/Debian: sudo apt update && sudo apt install -y vim curl
- Fedora:        sudo dnf install -y vim curl
- macOS:         brew install vim curl
MSG
  exit 1
fi

if ! need_cmd curl; then
  warn "curl が見つからないため、vim-plug の自動インストールをスキップする可能性があります。"
fi

if [ ! -d "${TARGET_DIR}/.git" ]; then
  info "リポジトリをクローンします: ${TARGET_DIR}"
  git clone "${REPO_URL}" "${TARGET_DIR}"
else
  info "既存リポジトリを更新します: ${TARGET_DIR}"
  git -C "${TARGET_DIR}" pull --ff-only
fi

if [ -f "${VIMRC_TARGET}" ]; then
  info "既存の ${VIMRC_TARGET} をバックアップします"
  cp "${VIMRC_TARGET}" "${VIMRC_TARGET}.bak.$(date +%Y%m%d%H%M%S)"
fi

cp "${TARGET_DIR}/vimrc_yurii_PKM_test.vim" "${VIMRC_TARGET}"
info "${VIMRC_TARGET} を作成しました"

if [ ! -f "${MAIN_VIMRC}" ]; then
  cat > "${MAIN_VIMRC}" <<'VIMRC'
" yurii_PKM の専用設定を読み込む
source ~/.vimrc_yurii_PKM_test
VIMRC
  info "${MAIN_VIMRC} を新規作成しました"
else
  if ! grep -Fq "source ~/.vimrc_yurii_PKM_test" "${MAIN_VIMRC}"; then
    printf '\n" yurii_PKM の専用設定\nsource ~/.vimrc_yurii_PKM_test\n' >> "${MAIN_VIMRC}"
    info "${MAIN_VIMRC} に source 設定を追記しました"
  else
    info "${MAIN_VIMRC} には既に source 設定があります"
  fi
fi

if need_cmd curl; then
  if [ ! -f "${PLUG_VIM}" ]; then
    info "vim-plug をインストールします"
    curl -fLo "${PLUG_VIM}" --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  else
    info "vim-plug は既にインストール済みです"
  fi
fi

info "プラグインをインストールします（初回は数分かかります）"
vim -u "${VIMRC_TARGET}" +"PlugInstall --sync" +qa || {
  warn "PlugInstall の自動実行に失敗しました。以下を手動実行してください:"
  echo "  vim -u ~/.vimrc_yurii_PKM_test +PlugInstall +qa"
}

cat <<'MSG'

セットアップ完了！

起動方法:
  vim
または
  vim -u ~/.vimrc_yurii_PKM_test
MSG
