
" ---------------------------------------------------------
" 文字コード
" ---------------------------------------------------------
set encoding=utf-8
set fileencoding=utf-8
set fileencodings=utf-8,euc-jp,sjis,cp932
set fileformats=unix,dos,mac

filetype plugin indent on
syntax on

" =========================================================
" 表示
" =========================================================
set number
set wrap
set linebreak
set breakindent
set showmatch
set matchtime=1
set laststatus=2

" =========================================================
" 検索
" =========================================================
set ignorecase
set smartcase
set incsearch
set hlsearch

" =========================================================
" インデント
" =========================================================
set autoindent
set smartindent
set expandtab
set tabstop=2
set shiftwidth=2

" =========================================================
" クリップボード
" =========================================================
if has('clipboard')
  set clipboard=unnamedplus
endif

inoremap <C-v> <C-r>+
vnoremap <C-v> "_d"+P
nnoremap <C-v> "+p
vnoremap <C-c> "+y

" =========================================================
" 移動
" =========================================================
nnoremap j gj
nnoremap k gk
nnoremap <Up> gk
nnoremap <Down> gj
inoremap <Up> <C-o>gk
inoremap <Down> <C-o>gj

" =========================================================
" 設定編集
" =========================================================
" 固定パスに依存させない。必要な場合だけ .vimrc 側で
"   let g:yurii_pkm_vimrc = expand('~/.vimrc')
" のように指定する。
if exists('g:yurii_pkm_vimrc') && !empty(trim(get(g:, "yurii_pkm_vimrc", "")))
  execute "nnoremap <silent> <leader>ev :edit " . fnameescape(expand(g:yurii_pkm_vimrc)) . "<CR>"
  execute "nnoremap <silent> <leader>sv :source " . fnameescape(expand(g:yurii_pkm_vimrc)) . "<CR>"
endif

" =========================================================
" yurii_PKM 見た目設定
" =========================================================
let g:yurii_pkm_link_color_gui = '#66CCFF'
let g:yurii_pkm_link_color_cterm = '81'

" =========================================================
" 自作プラグイン
" =========================================================

set backspace=indent,eol,start


" 既定アプリで開く

if has('wsl')
  nnoremap gm :call system('explorer.exe ' . shellescape(system('wslpath -w ' . expand('%:p'))))<CR>
else
  nnoremap gm :call system('xdg-open ' . shellescape(expand('%:p')) . ' &>/dev/null 2>&1 &')<CR>
endif

" 保存のショートカット
nnoremap \w :w<CR>
" UpdateAllのショート
nnoremap \ua :UpdateAll<CR>

" バックアップファイル無効化
set nobackup
set nowritebackup

" indexを最初から開く
autocmd VimEnter * call timer_start(0, {-> execute('YuriiIndex')}) | autocmd VimEnter * call timer_start(50, {-> execute('redraw!')})

" エラーを表示しない
autocmd FileType markdown highlight markdownError cterm=NONE gui=NONE
autocmd FileType markdown syntax clear markdownError
autocmd FileType markdown highlight link markdownError Normal
autocmd FileType markdown highlight link htmlError NONE
autocmd FileType markdown highlight htmlError cterm=NONE gui=NONE
autocmd FileType markdown syntax clear htmlError
autocmd FileType markdown highlight link htmlError Normal

" Rg検索のショートカット
nnoremap rg :Rg<CR>

let g:yurii_pkm_link_color_gui = '#2F6690'
let g:yurii_pkm_link_color_cterm = '24'

set background=light
colorscheme kalisi

" !系コマンドを常にsilentで実行
cmap <expr> <CR> getcmdtype() == ':' && getcmdline() =~ '^\s*!' ? '<C-\>e"silent " . getcmdline()<CR><CR>' : '<CR>'
" !コマンド後に自動でredraw
autocmd ShellCmdPost * redraw!
