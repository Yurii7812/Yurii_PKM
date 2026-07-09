
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
  if !has('wsl') || get(g:, 'yurii_wsl_use_system_clipboard', 0)
    set clipboard=unnamedplus
  endif
endif

inoremap <C-v> <C-r>+
vnoremap <C-v> "_d"+P
nnoremap <C-v> "+p
vnoremap <C-c> "+y


" =========================================================
" WSL パフォーマンス調整
" =========================================================
if has('wsl')
  " Windows クリップボード同期は Insert 中の体感遅延を起こしやすいので既定OFF
  let g:yurii_wsl_use_system_clipboard = get(g:, 'yurii_wsl_use_system_clipboard', 0)
  if !g:yurii_wsl_use_system_clipboard
    set clipboard=
  endif

  " 入力中イベントの発火頻度を下げる
  set updatetime=500
  set timeoutlen=500
  set ttimeoutlen=10
endif

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
function! s:open_with_default_app(path) abort
  let l:path = empty(a:path) ? expand('%:p') : a:path
  if empty(l:path)
    echohl WarningMsg | echom 'open-default: path is empty' | echohl None
    return
  endif

  if has('wsl')
    let l:winpath = substitute(system('wslpath -w ' . shellescape(l:path)), '\n\+$', '', '')
    if executable('wslview')
      call system('wslview ' . shellescape(l:path) . ' >/dev/null 2>&1 &')
    elseif !empty(l:winpath)
      call system('cmd.exe /C start "" ' . shellescape(l:winpath) . ' >NUL 2>&1')
    else
      echohl WarningMsg | echom 'open-default: failed to convert WSL path' | echohl None
    endif
  else
    call system('xdg-open ' . shellescape(l:path) . ' >/dev/null 2>&1 &')
  endif
endfunction

nnoremap <silent> gm :<C-u>call <SID>open_with_default_app(expand('%:p'))<CR>

" 保存のショートカット
nnoremap \w :w<CR>
" UpdateAllのショート
nnoremap \ua :UpdateAll<CR>

" 未保存の変更がある状態で別ファイルへ移動するときは、自動保存してから続行する
set autowriteall

" バックアップファイル無効化
set nobackup
set nowritebackup

" indexを最初から開く（不要なら let g:yurii_pkm_open_index_on_startup = 0）
if get(g:, 'yurii_pkm_open_index_on_startup', 1)
  augroup yurii_pkm_other_startup_index
    autocmd!
    autocmd VimEnter * call timer_start(0, {-> execute('YuriiIndex')})
  augroup END
endif

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
" !コマンド後の強制 redraw! は画面ちらつきの原因になるため既定OFF
if get(g:, 'yurii_force_redraw_after_shell', 0)
  augroup yurii_shell_redraw
    autocmd!
    autocmd ShellCmdPost * redraw
  augroup END
endif
