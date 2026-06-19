" =============================================================================
" plugin/yurii_PKM.vim
" yurii_PKM - Vimwiki 非依存 Markdown PKM プラグイン
" =============================================================================

if exists('g:loaded_yurii_pkm')
  finish
endif
let g:loaded_yurii_pkm = 1

" ---------------------------------------------------------------------------
" デフォルト設定
" ---------------------------------------------------------------------------

if !exists('g:yurii_pkm_root')
  let g:yurii_pkm_root = ''
endif
if !exists('g:yurii_pkm_default_child_prefix')
  let g:yurii_pkm_default_child_prefix = 'C'
endif
if !exists('g:yurii_pkm_default_quick_prefix')
  let g:yurii_pkm_default_quick_prefix = 'F'
endif
if !exists('g:yurii_pkm_default_atomic_prefix')
  let g:yurii_pkm_default_atomic_prefix = 'C'
endif
if !exists('g:yurii_pkm_history_max')
  let g:yurii_pkm_history_max = 200
endif
if !exists('g:yurii_pkm_history')
  let g:yurii_pkm_history = []
endif
" autosync: 保存後に自動更新するか (1=有効, 0=無効)
if !exists('g:yurii_pkm_autosync')
  let g:yurii_pkm_autosync = 1
endif
if !exists('g:yurii_pkm_auto_save_on_command')
  let g:yurii_pkm_auto_save_on_command = 1
endif
if !exists('g:yurii_pkm_realtime_link_sync')
  let g:yurii_pkm_realtime_link_sync = 1
endif
if !exists('g:yurii_pkm_markdown_conceal_links')
  " 既定は 1: [text](url) は text のみ表示
  let g:yurii_pkm_markdown_conceal_links = 1
endif
" リンク色は .vimrc 側で設定する想定

" Python スクリプトのパス
let s:plugin_root = fnamemodify(expand('<sfile>:p'), ':h:h')
if !exists('g:yurii_pkm_python')
  let g:yurii_pkm_python = s:plugin_root . '/python/yurii_pkm_sync.py'
endif
if !exists('g:yurii_pkm_expand_s_python')
  let g:yurii_pkm_expand_s_python = s:plugin_root . '/python/expand_s.py'
endif
if !exists('g:yurii_pkm_gallery_python')
  let g:yurii_pkm_gallery_python = s:plugin_root . '/python/gallery.py'
endif
if !exists('g:yurii_pkm_gallery_port')
  let g:yurii_pkm_gallery_port = 8765
endif

" ---------------------------------------------------------------------------
" コマンド定義
" ---------------------------------------------------------------------------

command! -nargs=? UpdateMD   call yurii_pkm#update_md(<q-args>)
command! -nargs=? UpdateAll  call yurii_pkm#update_all(<q-args>)
command! -nargs=? UpdateALL  call yurii_pkm#update_all(<q-args>)
command!          CheckPrefix call yurii_pkm#check_missing_prefix_in_current_dir()
command! -nargs=* NF         call yurii_pkm#new_quick(<q-args>)
command!          NA         call yurii_pkm#new_here_typed('A')
command! -nargs=* CA         call yurii_pkm#add_clipboard_to_branch()
command! -nargs=* CU         call yurii_pkm#add_clipboard_before_up()
command! -nargs=* TT         call yurii_pkm#add_clipboard_to_top()
command! -nargs=? NT         call yurii_pkm#rename_title(<q-args>)
command! -nargs=? RenameLinkText call yurii_pkm#rename_link_text(<q-args>)
command! -range=0 RenameChildLinkTitles call yurii_pkm#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
command! -range=0 RenameDownLinkTitles call yurii_pkm#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
command! -nargs=? LT         call yurii_pkm#rename_link_text(<q-args>)
command! -nargs=* BC         call yurii_pkm#add_from_clipboard(<f-args>)
command!          YN         call yurii_pkm#yank_name()
command!          AT         call yurii_pkm#at_add()
command!          Linkify    call yurii_pkm#linkify_filename_under_cursor()
command!          LinkifySelection call yurii_pkm#linkify_selection_new_note()
command!          LinkFixedToggle call yurii_pkm#toggle_fixed_link_text_under_cursor()
command!          PasteLink  call yurii_pkm#paste_clipboard_link_here()
command! -range=0 ToggleCheckbox call yurii_pkm#toggle_checkbox(<line1>, <line2>, <range>)
command!          SortYomi   call yurii_pkm#sort_yomi()
command! -range=0 -bang SortTime call yurii_pkm#sort_time(<bang>0, <line1>, <line2>, <range>)
command!          YuriiIndex call yurii_pkm#open_index()
command!          YuriiChooseIndexDir call yurii_pkm#choose_index_root()
command! -nargs=? ExpandLinks call yurii_pkm#expand_s_under_cursor(<q-args>)
command!          JumpLastLinkBeforeParent call yurii_pkm#jump_last_link_before_up()
command!          JumpParent call yurii_pkm#jump_up()
command!          JumpChildTop call yurii_pkm#jump_down_top()
command!          JumpChildBottom call yurii_pkm#jump_down_bottom()
command!          JumpLastLinkBeforeUp call yurii_pkm#jump_last_link_before_up()
command!          JumpUp     call yurii_pkm#jump_up()
command!          JumpDownTop call yurii_pkm#jump_down_top()
command!          JumpDownBottom call yurii_pkm#jump_down_bottom()

command! -nargs=? ExpandToT  call yurii_pkm#expand_s_under_cursor(<q-args>)
command! -nargs=? SE         call yurii_pkm#expand_s_under_cursor(<q-args>)
command!          RP         call yurii_pkm#rename_prefix()
command!          OutlineEdit call yurii_pkm#outline_edit()
command! -nargs=? Gallery    call yurii_pkm#open_gallery(<q-args>)
command! -nargs=? YuriiGallery call yurii_pkm#open_gallery(<q-args>)
command! -nargs=? GalleryFolder call yurii_pkm#open_folder_gallery(<q-args>)
command! -nargs=? YuriiGalleryFolder call yurii_pkm#open_folder_gallery(<q-args>)
" テーブル操作コマンド
command! -nargs=* TN         call yurii_pkm#table_new(<q-args>)
command! -nargs=* NewTable   call yurii_pkm#table_new(<q-args>)
command!          TA         call yurii_pkm#table_align_current()
command!          TRE        call yurii_pkm#table_row_edit()
command!          TCSV       call yurii_pkm#table_csv_edit()
command!          TableCsvEdit call yurii_pkm#table_csv_edit()
command!          TableCsvApplySaved call yurii_pkm#table_csv_editor_apply_saved()
command!          TCE        call yurii_pkm#table_to_csv()
command!          TableToCsv call yurii_pkm#table_to_csv()
command!          CsvToTable call yurii_pkm#csv_to_table()
command!          TableCsvNew call yurii_pkm#csv_new()
command!          TCN        call yurii_pkm#csv_new()
command!          TDR        call yurii_pkm#table_del_row()
command!          TDC        call yurii_pkm#table_del_col()
command!          TAR        call yurii_pkm#table_add_row()
command!          TAC        call yurii_pkm#table_add_col()
command! -nargs=* YuriiTable call yurii_pkm#table_new(<q-args>)

nnoremap <silent> \tn  :NewTable<CR>
nnoremap <silent> \ta  :TA<CR>
nnoremap <silent> \te  :TRE<CR>
nnoremap <silent> \tc  :TableToCsv<CR>
nnoremap <silent> \tt  :CsvToTable<CR>
nnoremap <silent> \tnc :TableCsvNew<CR>
nnoremap <silent> \tar :TAR<CR>
nnoremap <silent> \tac :TAC<CR>
nnoremap <silent> \tdr :TDR<CR>
nnoremap <silent> \tdc :TDC<CR>
nnoremap <silent> \ua  :UpdateAll<CR>

nnoremap <silent> \se  <Cmd>call <SID>expand_s_and_open()<CR>
nnoremap <nowait> <silent> mp  <Cmd>call yurii_pkm#rename_prefix()<CR>

" ---------------------------------------------------------------------------
" キーマッピング
" ---------------------------------------------------------------------------

" リンクナビゲーション
nnoremap <silent> <Tab>    <Cmd>call yurii_pkm#jump_link(1)<CR>
nnoremap <silent> <S-Tab>  <Cmd>call yurii_pkm#jump_link(0)<CR>
" 端末によっては Shift-Tab が <Esc>[Z として届くことがあるので保険を入れる
silent! execute "nnoremap <silent> \<Esc>[Z <Cmd>call yurii_pkm#jump_link(0)<CR>"
nnoremap <silent> <CR>     <Cmd>call yurii_pkm#open_link_under_cursor()<CR>
nnoremap <silent> <BS>     <Cmd>call yurii_pkm#go_back()<CR>
" 標準のジャンプリスト戻りでも、E37 を出さず保存してから移動する
nnoremap <silent> <C-O>    <Cmd>call yurii_pkm#save_before_normal_jump("\<C-O>")<CR>
nnoremap <nowait> <silent> bu  <Cmd>call yurii_pkm#jump_last_link_before_up()<CR>
nnoremap <nowait> <silent> ,,  <Cmd>call yurii_pkm#jump_up()<CR>
nnoremap <nowait> <silent> ,.  <Cmd>call yurii_pkm#jump_down_top()<CR>
nnoremap <nowait> <silent> ,/  <Cmd>call yurii_pkm#jump_down_bottom()<CR>

" ノート操作
nnoremap <nowait> <silent> nf  <Cmd>call yurii_pkm#new_quick_no_title()<CR>
nnoremap <nowait> <silent> mm  <Cmd>call yurii_pkm#new_prefix_note('N')<CR>
nnoremap <nowait> <silent> nk  <Cmd>call yurii_pkm#new_prefix_note('K')<CR>
vnoremap <nowait> <silent> nf  <Esc><Cmd>call yurii_pkm#visual_new_quick_no_title()<CR>
vnoremap <nowait> <silent> mm  <Esc><Cmd>call yurii_pkm#visual_new_prefix_note('N')<CR>
vnoremap <nowait> <silent> nk  <Esc><Cmd>call yurii_pkm#visual_new_prefix_note('K')<CR>
nnoremap <nowait> <silent> na  <Cmd>call yurii_pkm#new_here_typed('A')<CR>
" cu: クリップボードのリンクを Parent: セクションへ追加
nnoremap <nowait> <silent> cu  <Cmd>call yurii_pkm#add_clipboard_to_branch()<CR>
" ca: クリップボードのリンクを Child: に追加し、リンク先の Parent: に現在ノートを追加
nnoremap <nowait> <silent> ca  <Cmd>call yurii_pkm#add_clipboard_before_up()<CR>
nnoremap <nowait> <silent> tt  <Cmd>call yurii_pkm#add_clipboard_to_top()<CR>
" nt: タイトル変更（空欄から開始）
nnoremap <nowait> <silent> nt  <Cmd>call yurii_pkm#rename_title_with_default('')<CR>
" nT: 現在タイトルを残して編集
nnoremap <nowait> <silent> nT  <Cmd>call yurii_pkm#rename_title('')<CR>
" nl: リンク表示名変更（空欄から開始）
nnoremap <nowait> <silent> nl  <Cmd>call yurii_pkm#rename_link_text_with_default('')<CR>
" nL: 現在のリンク表示名を残して編集
nnoremap <nowait> <silent> nL  <Cmd>call yurii_pkm#rename_link_text('')<CR>
" nd: Child: のリンク表示名をリンク先 YAML title に更新
nnoremap <nowait> <silent> nd  <Cmd>RenameChildLinkTitles<CR>
vnoremap <nowait> <silent> nd  :<C-u>'<,'>RenameChildLinkTitles<CR>
" at: クリップボードのファイルのChildに現在ファイルへのリンクを追加
nnoremap <nowait> <silent> at  <Cmd>call yurii_pkm#at_add()<CR>
" bc: クリップボードのファイル名をChildに追加
nnoremap <nowait> <silent> bc  <Cmd>call yurii_pkm#add_from_clipboard()<CR>
" yn: 現在のファイル名をヤンク
nnoremap <nowait> <silent> yn  <Cmd>call yurii_pkm#yank_name()<CR>

" p: システムクリップボードを通常の Vim 動作で貼り付け
nnoremap <silent> p  "+p
" gp: 以前の独自貼り付け（改行末尾を落として行下に追加）
nnoremap <silent> gp <Cmd>call yurii_pkm#paste_charwise()<CR>
nnoremap <silent> \l        <Cmd>call yurii_pkm#linkify_filename_under_cursor()<CR>
xnoremap <silent> \l        :<C-u>call yurii_pkm#linkify_selection_new_note()<CR>
nnoremap <nowait> <silent> mx  <Cmd>ToggleCheckbox<CR>
xnoremap <nowait> <silent> mx  :<C-u>'<,'>ToggleCheckbox<CR>
nnoremap <silent> \L        <Cmd>call yurii_pkm#toggle_fixed_link_text_under_cursor()<CR>
nnoremap <silent> \p        <Cmd>call yurii_pkm#paste_clipboard_link_here()<CR>
xnoremap <silent> \p        :<C-u>call yurii_pkm#linkify_selection_from_clipboard()<CR>
nnoremap <silent> \oe       <Cmd>OutlineEdit<CR>
nnoremap <silent> \gi       <Cmd>call yurii_pkm#open_gallery_smart()<CR>

" ---------------------------------------------------------------------------
" Shift-Tab / BackTab の端末互換
" ---------------------------------------------------------------------------

function! s:setup_backtab() abort
  if has('gui_running')
    return
  endif
  " 多くの端末は Shift-Tab を ESC [ Z で送る
  silent! execute "set <S-Tab>=\<Esc>[Z"
endfunction

call s:setup_backtab()
" ---------------------------------------------------------------------------
" expand_s_and_open: \se で展開して T ファイルを警告なしで開く
" ---------------------------------------------------------------------------

function! s:expand_s_and_open() abort
  let l:file = expand('%:p')
  let l:root = fnamemodify(l:file, ':h')
  let l:py   = g:yurii_pkm_expand_s_python
  let l:cmd  = printf('python3 %s expand_s %s %s 1',
        \ shellescape(l:py),
        \ shellescape(l:file),
        \ shellescape(l:root))
  let l:result = system(l:cmd)
  if v:shell_error
    echohl ErrorMsg | echo 'expand_s failed: ' . l:result | echohl None
    return
  endif
  let l:t_path = substitute(l:result, '\n\+$', '', '')
  " BS で戻れるよう元ファイルを履歴に積む（go_back が期待する辞書形式）
  call add(g:yurii_pkm_history, {'file': l:file, 'pos': getpos('.')})
  if len(g:yurii_pkm_history) > g:yurii_pkm_history_max
    call remove(g:yurii_pkm_history, 0)
  endif
  " T ファイルを開く
  execute 'keepjumps edit ' . fnameescape(l:t_path)
endfunction




" ---------------------------------------------------------------------------
" Markdown table helpers (vimwiki-like)
"   Insert mode <Tab>/<S-Tab>/<CR> はテーブル内のみ挙動変更
"   コマンド一覧:
"     :TN [{cols} {rows}]  新規テーブル挿入
"     :TA                  整形（列幅を揃える）
"     :TRE                 行を別バッファで編集
"     :TCE                 CSV バッファで編集
"     :TDR / :TDC          行・列を削除
"     :TAR / :TAC          行・列を追加
" ---------------------------------------------------------------------------

augroup yurii_pkm_table
  autocmd!
  autocmd FileType markdown,vimwiki call s:setup_table_keys()
  autocmd BufRead,BufNewFile *.md   call s:setup_table_keys()
augroup END

function! s:setup_table_keys() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return
  endif
  inoremap <buffer><silent> <Tab>   <C-o>:call yurii_pkm#table_tab_action()<CR>
  inoremap <buffer><silent> <S-Tab> <C-o>:call yurii_pkm#table_stab_action()<CR>
  inoremap <buffer><silent> <CR>    <C-o>:call yurii_pkm#table_cr_action()<CR>
  " <leader>t + 1文字: テーブル操作
  "   ta  整形          te  行編集       tc  CSV編集
  "   tdr 行削除        tdc 列削除
  "   tar 行追加        tac 列追加
  nnoremap <buffer><silent> <leader>ta  <Cmd>TA<CR>
  nnoremap <buffer><silent> <leader>te  <Cmd>TRE<CR>
  nnoremap <buffer><silent> <leader>tc  <Cmd>TCSV<CR>
  nnoremap <buffer><silent> <leader>tdr <Cmd>TDR<CR>
  nnoremap <buffer><silent> <leader>tdc <Cmd>TDC<CR>
  nnoremap <buffer><silent> <leader>tar <Cmd>TAR<CR>
  nnoremap <buffer><silent> <leader>tac <Cmd>TAC<CR>
endfunction

" ---------------------------------------------------------------------------
" Markdown リンクの concealment
"   [テキスト](url)  →  テキスト  のみ表示
"   concealcursor=n で、カーソルがある行だけ展開表示
" ---------------------------------------------------------------------------

augroup yurii_pkm_conceal
  autocmd!
  autocmd FileType markdown,vimwiki call s:setup_conceal()
  autocmd BufRead,BufNewFile *.md   call s:setup_conceal()
augroup END

function! s:setup_conceal() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return
  endif

  if get(g:, 'yurii_pkm_markdown_conceal_links', 0)
    setlocal conceallevel=2
    setlocal concealcursor=n
    " conceal + linebreak の組み合わせで、隠した URL 部分を基準に不自然な折返しが
    " 発生しやすいため、markdown では行折返しを通常の wrap に戻す。
    setlocal nolinebreak
  else
    setlocal conceallevel=0
    setlocal concealcursor=
    setlocal linebreak
  endif

  " 再実行時の重複定義を防ぐ
  silent! syntax clear yuriiLinkRegion
  silent! syntax clear yuriiLinkText
  silent! syntax clear yuriiConcealOpen
  silent! syntax clear yuriiConcealClose
  silent! syntax clear yuriiEmptyBracket
  silent! syntax clear yuriiCheckboxBracket
  silent! syntax clear yuriiCheckedBracket

  " リンク全体は region で保持し、見える本文だけを水色にする
  syntax region yuriiLinkRegion start=/\[\ze[^\] \n][^\]\n]*\](\([^)\n]\+\))/ end=/\](\([^)\n]\+\))/ keepend oneline contains=yuriiLinkText,yuriiConcealOpen,yuriiConcealClose
  syntax match yuriiLinkText /\%(\[\)\@<=[^\] \n][^\]\n]*\ze\](\([^)\n]\+\))/ contained
  let l:link_color_gui = get(g:, 'yurii_pkm_link_color_gui', '#66CCFF')
  let l:link_color_cterm = get(g:, 'yurii_pkm_link_color_cterm', '81')
  execute 'highlight yuriiLinkText term=underline cterm=underline gui=underline ctermfg=' . l:link_color_cterm . ' guifg=' . l:link_color_gui

  " [ と ](xxx) を隠して、リンク本文だけ見せる
  syntax match yuriiConcealOpen /\[/ contained conceal
  syntax match yuriiConcealClose /\](\([^)\n]\+\))/ contained conceal
  syntax match yuriiEmptyBracket /\[\]/ containedin=ALL
  syntax match yuriiCheckboxBracket /\[ \]/ containedin=ALL
  syntax match yuriiCheckedBracket /\[[xX]\]/ containedin=ALL
  highlight default link yuriiEmptyBracket Normal
  highlight default link yuriiCheckboxBracket Normal
  highlight default link yuriiCheckedBracket Normal

  " エラー強調を無効化（[] の直後にリンクがある場合などの赤表示を防ぐ）
  highlight default link markdownError Normal
  highlight default link htmlError Normal
  highlight! link markdownError Normal
  highlight! link htmlError Normal
endfunction

" ---------------------------------------------------------------------------
" Persistent undo: ファイルをまたいでも・再起動後も undo 履歴を保持
" ---------------------------------------------------------------------------

if !exists('g:yurii_pkm_persistent_undo')
  let g:yurii_pkm_persistent_undo = 1
endif

if g:yurii_pkm_persistent_undo
  set undofile
  set undolevels=10000
  set undoreload=100000
endif

" ---------------------------------------------------------------------------
" AutoSync: BufWritePost で update_one を起動
" ---------------------------------------------------------------------------

augroup yurii_pkm_autosync
  autocmd!
  autocmd BufWritePost *.md call s:on_write_post()
  autocmd BufReadPost,BufEnter *.md call yurii_pkm#realtime_sync_snapshot()
  autocmd TextChanged,TextChangedI *.md call yurii_pkm#realtime_sync_on_text_changed()
  autocmd FileChangedShell *.md let v:fcs_choice = 'reload'
augroup END

function! s:on_write_post() abort
  if !g:yurii_pkm_autosync | return | endif
  call yurii_pkm#autosync_on_save()
endfunction

function! s:normalize_cmdline(cmdline) abort
  let l:cmd = trim(a:cmdline)
  while 1
    let l:new = substitute(l:cmd,
          \ '^\c\%(silent!?\|verbose\|keepalt\|keeppatterns\|keepjumps\|lockmarks\|confirm\|noswapfile\)\s\+', '', '')
    if l:new ==# l:cmd
      break
    endif
    let l:cmd = trim(l:new)
  endwhile
  return l:cmd
endfunction

function! s:auto_save_before_command() abort
  if !get(g:, 'yurii_pkm_auto_save_on_command', 1)
    return
  endif
  if getcmdtype() !=# ':'
    return
  endif
  if &buftype !=# '' || !&modifiable || !&modified || empty(expand('%:p'))
    return
  endif

  let l:cmd = s:normalize_cmdline(getcmdline())
  if empty(l:cmd)
    return
  endif

  " 保存せずに抜けたい系のコマンドは除外
  if l:cmd =~# '^\c\%(q\%[uit]\|qa\%[ll]\|cq\%[uit]\|cquit\|bd\%[elete]\|bw\%[ipeout]\|bunload\|bdel\|bwipe\)\>.*!\?$'
    return
  endif

  silent! update
endfunction

augroup yurii_pkm_auto_save_on_command
  autocmd!
  autocmd CmdlineLeave : call s:auto_save_before_command()
augroup END

augroup yurii_pkm_startup_root_init
  autocmd!
  autocmd VimEnter * ++once call yurii_pkm#startup_restore_root()
augroup END

augroup yurii_pkm_startup_prefix_check
  autocmd!
augroup END

" ---------------------------------------------------------------------------
" CopyStack コマンド
" ---------------------------------------------------------------------------
nnoremap <silent> \sc <Cmd>CopyStack<CR>
command! CopyStack call yurii_pkm#stack_copy_toggle()
