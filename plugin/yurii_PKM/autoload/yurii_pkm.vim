" =============================================================================
" autoload/yurii_pkm.vim
" yurii_PKM - Vimwiki非依存 Markdown PKM プラグイン (autoload)
" =============================================================================

" ---------------------------------------------------------------------------
" Internal helpers
" ---------------------------------------------------------------------------

let s:link_pat = '\v\[[^\]]+\]\([^)]*\)'

function! s:sep() abort
  return has('win32') ? '\' : '/'
endfunction

function! s:python_cmd() abort
  if has('win32')
    return 'python'
  endif
  return executable('python3') ? 'python3' : 'python'
endfunction

function! s:is_markdown_file(path) abort
  return tolower(fnamemodify(a:path, ':e')) ==# 'md'
endfunction

function! s:is_markdown_target(target) abort
  return tolower(fnamemodify(a:target, ':e')) ==# 'md'
endfunction

function! s:run_sync(args_list) abort
  if !filereadable(g:yurii_pkm_python)
    echoerr 'yurii_PKM: Python script not found: ' . g:yurii_pkm_python
    return ''
  endif
  let l:cmd = s:python_cmd()
  for a in a:args_list
    let l:cmd .= ' ' . shellescape(a)
  endfor
  return system(l:cmd)
endfunction

" ---------------------------------------------------------------------------
" Title cache (session-level)
" ---------------------------------------------------------------------------

let s:title_cache = {}

function! yurii_pkm#clear_title_cache() abort
  let s:title_cache = {}
endfunction

function! s:get_title(filepath) abort
  let l:fp = fnamemodify(a:filepath, ':p')
  if !s:is_markdown_file(l:fp)
    return ''
  endif
  if has_key(s:title_cache, l:fp)
    return s:title_cache[l:fp]
  endif
  if !filereadable(l:fp)
    return ''
  endif
  let l:lines = readfile(l:fp, '', 30)
  let l:in_yaml = 0
  for l:line in l:lines
    if l:line =~# '^---\s*$'
      if l:in_yaml | break | endif
      let l:in_yaml = 1
      continue
    endif
    if l:in_yaml && l:line =~? '^title:\s*'
      let l:title = trim(matchstr(l:line, ':\s*\zs.*'))
      let l:title = substitute(l:title, '^[\"'']\|[\"'']$', '', 'g')
      let s:title_cache[l:fp] = l:title
      return l:title
    endif
    if !l:in_yaml && l:line =~# '^#\+\s\+'
      let l:title = trim(substitute(l:line, '^#\+\s\+', '', ''))
      let s:title_cache[l:fp] = l:title
      return l:title
    endif
  endfor
  let l:stem = fnamemodify(l:fp, ':t:r')
  let s:title_cache[l:fp] = l:stem
  return l:stem
endfunction

" ---------------------------------------------------------------------------
" Current file helpers
" ---------------------------------------------------------------------------

function! yurii_pkm#current_file() abort
  return expand('%:p')
endfunction

function! yurii_pkm#current_title() abort
  let l:lines = getline(1, min([30, line('$')]))
  let l:in_yaml = 0
  for l:line in l:lines
    if l:line =~# '^---\s*$'
      if l:in_yaml | break | endif
      let l:in_yaml = 1
      continue
    endif
    if l:in_yaml && l:line =~? '^title:\s*'
      let l:t = trim(matchstr(l:line, ':\s*\zs.*'))
      return substitute(l:t, '^[\"'']\|[\"'']$', '', 'g')
    endif
    if !l:in_yaml && l:line =~# '^#\+\s\+'
      return trim(substitute(l:line, '^#\s\+', '', ''))
    endif
  endfor
  return expand('%:t:r')
endfunction

function! s:outline_collect() abort
  let l:items = []
  let l:max_lnum = line('$')
  let lnum = 1
  while lnum <= l:max_lnum
    let l:line = getline(lnum)
    if l:line =~# '^\s*#\+\s\+'
      let l:indent = matchstr(l:line, '^\s*')
      let l:head = matchstr(l:line, '#\+')
      let l:title = substitute(l:line, '^\s*#\+\s\+', '', '')
      let l:title = substitute(l:title, '^\s\+', '', '')
      let l:title = substitute(l:title, '\s\+$', '', '')

      call add(l:items, {
            \ 'src_lnum': lnum,
            \ 'indent': l:indent,
            \ 'level': strlen(l:head),
            \ 'title': l:title,
            \ })
    endif
    let lnum += 1
  endwhile

  return l:items
endfunction

function! s:outline_editor_lines(items) abort
  let l:lines = []
  call add(l:lines, '# OutlineEdit: 見出しを編集して :write で反映')
  call add(l:lines, '# <- / -> : 見出しレベル変更（# の数を減増）')
  call add(l:lines, '# Visual選択して <- / -> : 選択範囲を一括変更')
  call add(l:lines, '# q / ZZ / :OutlineApply で反映（Q は保存せず閉じる）')
  call add(l:lines, '')

  for l:item in a:items
    call add(l:lines, repeat('#', l:item.level) . ' ' . l:item.title)
  endfor
  return l:lines
endfunction

function! s:outline_shift_range(first, last, delta) abort
  let l:base = get(b:, 'yurii_outline_base', 6)
  let l:last_edit = l:base + len(get(b:, 'yurii_outline_items', [])) - 1
  let l:start = max([a:first, l:base])
  let l:end = min([a:last, l:last_edit])
  if l:start > l:end
    return
  endif

  for lnum in range(l:start, l:end)
    let l:line = getline(lnum)
    if l:line !~# '^\s*#\+\s\+'
      continue
    endif
    let l:level = strlen(matchstr(l:line, '#\+')) + a:delta
    let l:level = max([1, l:level])
    let l:title = trim(substitute(l:line, '^\s*#\+\s\+', '', ''))
    call setline(lnum, repeat('#', l:level) . ' ' . l:title)
  endfor
endfunction

function! yurii_pkm#outline_shift_current(delta) abort
  call s:outline_shift_range(line('.'), line('.'), a:delta)
endfunction

function! yurii_pkm#outline_shift_visual(delta) range abort
  call s:outline_shift_range(a:firstline, a:lastline, a:delta)
endfunction

function! yurii_pkm#outline_editor_apply() abort
  if !get(b:, 'yurii_outline_editor', 0)
    return
  endif
  let l:src_buf = get(b:, 'yurii_outline_src_bufnr', -1)
  let l:items = get(b:, 'yurii_outline_items', [])
  let l:base = get(b:, 'yurii_outline_base', 6)
  if l:src_buf < 0 || empty(l:items)
    echoerr 'OutlineEdit: invalid editor state'
    return
  endif

  for l:i in range(0, len(l:items) - 1)
    let l:src = l:items[l:i]
    let l:line = trim(getline(l:base + l:i))
    if l:line =~# '^#\+\s\+'
      let l:new_level = strlen(matchstr(l:line, '^#\+'))
      let l:new_title = trim(substitute(l:line, '^#\+\s\+', '', ''))
    else
      let l:new_level = max([1, get(l:src, 'level', 1)])
      let l:new_title = empty(l:line) ? get(l:src, 'title', '') : l:line
    endif
    let l:new_line = get(l:src, 'indent', '') . repeat('#', l:new_level) . ' ' . l:new_title
    call setbufline(l:src_buf, l:src.src_lnum, l:new_line)
  endfor

  setlocal nomodified
  echom 'OutlineEdit: 反映しました'
endfunction

function! yurii_pkm#outline_edit() abort
  if !s:is_markdown_file(expand('%:p'))
    echoerr 'yurii_PKM: OutlineEdit は Markdown ファイルでのみ利用できます'
    return
  endif

  let l:items = s:outline_collect()

  if empty(l:items)
    echom 'yurii_PKM: 見出しが見つかりませんでした'
    return
  endif

  let l:origin_win = win_getid()
  vertical botright new
  execute 'file ' . fnameescape('[YuriiOutlineEdit]')

  call setline(1, s:outline_editor_lines(l:items))

  let b:yurii_outline_editor = 1
  let b:yurii_outline_src_bufnr = winbufnr(l:origin_win)
  let b:yurii_outline_items = deepcopy(l:items)
  let b:yurii_outline_base = 6

  setlocal buftype=acwrite
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=markdown
  setlocal nonumber
  setlocal norelativenumber
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal nowrap
  setlocal modifiable

  augroup yurii_pkm_outline_editor
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> call yurii_pkm#outline_editor_apply()
  augroup END
  command! -buffer OutlineApply call yurii_pkm#outline_editor_apply()
  nnoremap <silent><buffer> q  <Cmd>call yurii_pkm#outline_editor_apply()<CR><Cmd>bd!<CR>
  nnoremap <silent><buffer> Q  <Cmd>bd!<CR>
  nnoremap <silent><buffer> ZZ <Cmd>call yurii_pkm#outline_editor_apply()<CR><Cmd>bd!<CR>

  nnoremap <silent><buffer> <Left>  <Cmd>call yurii_pkm#outline_shift_current(-1)<CR>
  nnoremap <silent><buffer> <Right> <Cmd>call yurii_pkm#outline_shift_current(1)<CR>
  xnoremap <silent><buffer> <Left>  :<C-u>call yurii_pkm#outline_shift_visual(-1)<CR>
  xnoremap <silent><buffer> <Right> :<C-u>call yurii_pkm#outline_shift_visual(1)<CR>

  call cursor(b:yurii_outline_base, 1)
endfunction


function! s:state_dir() abort
  if exists('*stdpath')
    return stdpath('data') . s:sep() . 'yurii_pkm'
  endif
  return expand('~/.vim/yurii_pkm')
endfunction

function! s:root_state_file() abort
  return s:state_dir() . s:sep() . 'root.txt'
endfunction

function! s:load_persisted_root() abort
  let l:file = s:root_state_file()
  if !filereadable(l:file)
    return ''
  endif
  let l:lines = readfile(l:file)
  if empty(l:lines)
    return ''
  endif
  let l:root = trim(l:lines[0])
  if empty(l:root)
    return ''
  endif
  return fnamemodify(expand(l:root), ':p')
endfunction

function! s:save_persisted_root(root) abort
  if empty(a:root)
    return
  endif
  let l:dir = s:state_dir()
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  call writefile([fnamemodify(a:root, ':p')], s:root_state_file())
endfunction

function! s:get_pkm_root() abort
  let l:root = ''
  if exists('g:yurii_pkm_root')
    let l:root = trim(get(g:, 'yurii_pkm_root', ''))
  endif
  if empty(l:root)
    let l:root = s:load_persisted_root()
    if !empty(l:root)
      let g:yurii_pkm_root = l:root
    endif
  endif
  if empty(l:root)
    return ''
  endif
  return fnamemodify(expand(l:root), ':p')
endfunction

function! s:index_path(root) abort
  return fnamemodify(a:root, ':p') . s:sep() . 'index.md'
endfunction

function! s:index_template() abort
  return [
        \ '---',
        \ 'time: ' . yurii_pkm#timestamp_yaml(),
        \ 'title: Index',
        \ '---',
        \ '',
        \ '# Index',
        \ '',
        \ ]
endfunction

function! s:setup_persistent_undo_for_root(root) abort
  if !get(g:, 'yurii_pkm_persistent_undo', 1)
    return
  endif
  if empty(a:root)
    return
  endif
  let l:undo_dir = fnamemodify(a:root, ':p') . s:sep() . '.undo'
  if !isdirectory(l:undo_dir)
    call mkdir(l:undo_dir, 'p')
  endif
  execute 'set undodir=' . fnameescape(l:undo_dir)
  set undofile
  set undolevels=10000
  set undoreload=100000
endfunction

function! yurii_pkm#init_persistent_undo_if_ready() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || !isdirectory(l:root)
    return
  endif
  if !filereadable(s:index_path(l:root))
    return
  endif
  call s:setup_persistent_undo_for_root(l:root)
endfunction

let s:startup_root_recovery_active = 0
let s:index_created_recently = 0

function! s:mark_index_created() abort
  let s:index_created_recently = 1
endfunction

function! s:consume_index_created_flag() abort
  let l:created = get(s:, 'index_created_recently', 0)
  let s:index_created_recently = 0
  return l:created
endfunction

function! s:timer_edit_file_cb(...) abort
  " timer_start() の callback 引数順は Vim 実装/呼び出し方で差が出ることがあるため、
  " 文字列の引数を path として拾う。
  let l:path = ''
  if a:0 >= 1 && type(a:1) == v:t_string
    let l:path = a:1
  elseif a:0 >= 2 && type(a:2) == v:t_string
    let l:path = a:2
  endif
  if empty(l:path)
    return
  endif
  execute 'edit ' . fnameescape(l:path)

endfunction

function! s:timer_redraw_cb(timer) abort
  redraw!
endfunction

function! s:open_index_with_delay(index_path) abort
  call yurii_pkm#push_history()
  call timer_start(0, function('s:timer_edit_file_cb', [a:index_path]))
  call timer_start(50, function('s:timer_redraw_cb'))
endfunction

function! s:startup_recover_missing_root() abort
  let l:new_root = s:prompt_index_root()
  if empty(l:new_root)
    return ''
  endif

  let g:yurii_pkm_root = l:new_root
  call s:save_persisted_root(l:new_root)

  let l:index = s:index_path(l:new_root)
  if !filereadable(l:index)
    let l:ans = tolower(trim(input('Create index.md? y/n: ')))
    if l:ans !=# 'y'
      echom 'index.md not created'
      return l:new_root
    endif
    if !isdirectory(l:new_root)
      call mkdir(l:new_root, 'p')
    endif
    call s:setup_persistent_undo_for_root(l:new_root)
    call writefile(s:index_template(), l:index)
    call s:mark_index_created()
    call yurii_pkm#clear_title_cache()
    echom 'Created: ' . l:index
  endif

  if filereadable(l:index)
    execute 'cd ' . fnameescape(l:new_root)
    if s:consume_index_created_flag()
      call s:open_index_with_delay(l:index)
    else
      call yurii_pkm#push_history()
      execute 'edit ' . fnameescape(l:index)
    endif
  endif
  return l:new_root
endfunction

function! yurii_pkm#startup_restore_root() abort
  if get(s:, 'startup_root_recovery_active', 0)
    return
  endif
  let s:startup_root_recovery_active = 1
  try
    let l:root = s:get_pkm_root()
    if empty(l:root)
      return
    endif
    if isdirectory(l:root) && filereadable(s:index_path(l:root))
      let g:yurii_pkm_root = l:root
      call s:setup_persistent_undo_for_root(l:root)
      return
    endif

    if !isdirectory(l:root)
      echom 'Remembered PKM root not found: ' . l:root
      call s:startup_recover_missing_root()
      return
    endif

    echom 'Remembered index not found: ' . s:index_path(l:root)
    let g:yurii_pkm_root = l:root
    call s:save_persisted_root(l:root)
    let l:ans = tolower(trim(input('Create index.md? y/n: ')))
    if l:ans !=# 'y'
      echom 'index.md not created'
      return
    endif
    if !isdirectory(l:root)
      return
    endif
    let l:index = s:index_path(l:root)
    call s:setup_persistent_undo_for_root(l:root)
    call writefile(s:index_template(), l:index)
    call s:mark_index_created()
    call yurii_pkm#clear_title_cache()
    execute 'cd ' . fnameescape(l:root)
    if s:consume_index_created_flag()
      call s:open_index_with_delay(l:index)
    else
      call yurii_pkm#push_history()
      execute 'edit ' . fnameescape(l:index)
    endif
    echom 'Created: ' . l:index
  finally
    let s:startup_root_recovery_active = 0
  endtry
endfunction

" ディレクトリ選択 -> Index作成 -> Indexを開く までを一括で行うヘルパー
" a:open_index: 作成後にIndexを開くかどうか (1=開く, 0=開かない)
" 戻り値: 設定したrootのパス、キャンセル時は ''
function! s:setup_root_and_index(open_index) abort
  " Step1: ディレクトリ選択
  let l:default = s:get_pkm_root()
  if empty(l:default)
    let l:default = getcwd()
  endif
  try
    let l:root = trim(input('Index directory: ', l:default, 'dir'))
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return ''
  endtry
  if empty(l:root)
    echo 'Cancelled'
    return ''
  endif
  let l:root = fnamemodify(expand(l:root), ':p')

  if !isdirectory(l:root)
    call mkdir(l:root, 'p')
  endif
  let g:yurii_pkm_root = l:root
  call s:save_persisted_root(l:root)
  call s:setup_persistent_undo_for_root(l:root)

  " Step2: Index作成確認
  let l:index = s:index_path(l:root)
  if !filereadable(l:index)
    let l:ans = tolower(trim(input('Create index.md? y/n: ')))
    if l:ans ==# 'y'
      call writefile(s:index_template(), l:index)
      call s:mark_index_created()
      call yurii_pkm#clear_title_cache()
      echom 'Created: ' . l:index
    else
      echom 'index.md not created'
      return l:root
    endif
  endif

  " Step3: Indexを開く
  if a:open_index && filereadable(l:index)
    execute 'cd ' . fnameescape(l:root)
    if s:consume_index_created_flag()
      call s:open_index_with_delay(l:index)
    else
      call yurii_pkm#push_history()
      execute 'edit ' . fnameescape(l:index)
    endif
  endif

  return l:root
endfunction

function! s:prompt_index_root() abort
  let l:default = s:get_pkm_root()
  if empty(l:default)
    let l:default = getcwd()
  endif
  try
    let l:dir = trim(input('Index directory: ', l:default, 'dir'))
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return ''
  endtry
  if empty(l:dir)
    echo 'Cancelled'
    return ''
  endif
  return fnamemodify(expand(l:dir), ':p')
endfunction

function! yurii_pkm#ensure_root_and_index() abort
  let l:root = s:get_pkm_root()

  if get(s:, 'startup_root_recovery_active', 0)
    if !empty(l:root) && filereadable(s:index_path(l:root))
      return l:root
    endif
    return ''
  endif

  " rootもIndexも正常
  if !empty(l:root) && filereadable(s:index_path(l:root))
    let g:yurii_pkm_root = l:root
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
    return l:root
  endif

  " rootは設定済みだがディレクトリが消えている → 選び直し
  if !empty(l:root) && !isdirectory(l:root)
    return s:setup_root_and_index(1)
  endif

  " rootは設定済みでディレクトリはあるがIndexがない → Index作成だけ
  if !empty(l:root)
    let g:yurii_pkm_root = l:root
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
    let l:index = s:index_path(l:root)
    let l:ans = tolower(trim(input('Create index.md? y/n: ')))
    if l:ans ==# 'y'
      call writefile(s:index_template(), l:index)
      call s:mark_index_created()
      call yurii_pkm#clear_title_cache()
      echom 'Created: ' . l:index
      return l:root
    else
      echom 'index.md not created'
      return ''
    endif
  endif

  " rootが未設定 → ディレクトリ選択から
  return s:setup_root_and_index(0)
endfunction

function! yurii_pkm#choose_index_root() abort
  let l:current_root = s:get_pkm_root()
  let l:new_root = s:setup_root_and_index(1)
  if empty(l:new_root)
    return ''
  endif
  if !empty(l:current_root) && fnamemodify(l:current_root, ':p') !=# fnamemodify(l:new_root, ':p')
    echom 'Switched PKM root to: ' . l:new_root
  else
    echom 'PKM root set to: ' . l:new_root
  endif
  return l:new_root
endfunction

function! s:current_dir_for_prefix_check() abort
  let l:file = expand('%:p')
  if !empty(l:file)
    return fnamemodify(l:file, ':p:h')
  endif
  return getcwd()
endfunction

function! s:is_in_pkm_root(path) abort
  let l:root = s:get_pkm_root()
  if empty(l:root)
    return 0
  endif
  let l:path = fnamemodify(a:path, ':p')
  return l:path =~# '^' . escape(l:root, '\')
endfunction

function! s:missing_prefix_files_in_dir(dir) abort
  let l:files = []
  for l:path in sort(glob(a:dir . '/*', 0, 1))
    if !filereadable(l:path)
      continue
    endif
    let l:name = fnamemodify(l:path, ':t')
    if l:name ==# 'index.md' || l:name =~# '^\.'
      continue
    endif
    if l:name =~# '^[A-Z]_'
      continue
    endif
    call add(l:files, l:path)
  endfor
  return l:files
endfunction

function! s:rename_missing_prefix_files(dir, files) abort
  let l:cur = expand('%:p')
  let l:renamed = []
  for l:old in a:files
    let l:new = fnamemodify(l:old, ':h') . '/M_' . fnamemodify(l:old, ':t')
    if filereadable(l:new) || isdirectory(l:new)
      echom 'skip (already exists): ' . fnamemodify(l:new, ':t')
      continue
    endif
    if rename(l:old, l:new) != 0
      echom 'rename failed: ' . fnamemodify(l:old, ':t')
      continue
    endif
    if !empty(l:cur) && fnamemodify(l:cur, ':p') ==# fnamemodify(l:old, ':p')
      execute 'silent keepalt file ' . fnameescape(l:new)
      let l:cur = l:new
    endif
    call add(l:renamed, fnamemodify(l:new, ':t'))
  endfor
  return l:renamed
endfunction

function! yurii_pkm#check_missing_prefix_in_current_dir() abort
  return 1
endfunction

function! yurii_pkm#check_missing_prefix_in_current_dir_once() abort
  return
endfunction

" ---------------------------------------------------------------------------
" Section helpers (buffer-level)
" ---------------------------------------------------------------------------

function! s:bare_section_name(text) abort
  let l:s = trim(a:text)
  let l:s = substitute(l:s, '^#\+\s*', '', '')
  return tolower(l:s)
endfunction

function! s:is_section_header_text(text, name) abort
  return s:bare_section_name(a:text) ==# tolower(a:name)
endfunction

function! s:find_section_index_in_lines(lines, name) abort
  let l:found = -1
  let l:in_fence = 0
  for l:i in range(0, len(a:lines) - 1)
    let l:s = trim(a:lines[l:i])
    if l:s =~# '^```'
      let l:in_fence = !l:in_fence
    endif
    if !l:in_fence && s:is_section_header_text(l:s, a:name)
      let l:found = l:i
    endif
  endfor
  return l:found
endfunction

" Return line number (1-based) of section header, or 0
function! s:find_section_line(name) abort
  let l:found = 0
  let l:in_fence = 0
  for l:i in range(1, line('$'))
    let l:s = trim(getline(l:i))
    if l:s =~# '^```'
      let l:in_fence = !l:in_fence
    endif
    if !l:in_fence && s:is_section_header_text(l:s, a:name)
      let l:found = l:i
    endif
  endfor
  return l:found
endfunction

" Return line number just before 'back' section (for Branch append), or 0
function! s:branch_end_line() abort
  let l:back = s:find_section_line('back')
  if l:back > 0
    return l:back - 1
  endif
  return line('$')
endfunction


" Return last line of 'back' section (before ___ or EOF), or 0
function! s:back_end_line() abort
  let l:back = s:find_section_line('back')
  if l:back <= 0
    return 0
  endif
  for l:i in range(l:back + 1, line('$'))
    if getline(l:i) =~# '^_\{3,}\s*$'
      return l:i - 1
    endif
  endfor
  return line('$')
endfunction

function! s:in_back_section(lnum) abort
  let l:back = s:find_section_line('back')
  if l:back <= 0
    return 0
  endif
  return a:lnum >= l:back + 1
endfunction

function! s:find_reciprocal_link_pos(target_path, source_name) abort
  if !filereadable(a:target_path)
    return [0, 0]
  endif
  let l:lines = readfile(a:target_path)
  let l:back_line = len(l:lines) + 1
  for l:i in range(0, len(l:lines) - 1)
    if s:is_section_header_text(l:lines[l:i], 'back')
      let l:back_line = l:i + 1
      break
    endif
  endfor

  for l:lnum in range(1, l:back_line - 1)
    let l:line = get(l:lines, l:lnum - 1, '')
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, s:link_pat, l:start)
      if len(l:m) < 3 || l:m[1] < 0
        break
      endif
      let l:parts = matchlist(l:m[0], '\v\[([^\]]+)\]\(([^)]*)\)')
      let l:target = fnamemodify(get(l:parts, 2, ''), ':t')
      if l:target ==# a:source_name
        return [l:lnum, l:m[1] + 1]
      endif
      let l:start = l:m[2]
    endwhile
  endfor
  return [0, 0]
endfunction


" ---------------------------------------------------------------------------
" Link navigation
" ---------------------------------------------------------------------------

function! yurii_pkm#jump_link(forward) abort
  let l:flags = a:forward ? 'W' : 'bW'
  if !search(s:link_pat, l:flags)
    echo 'No more links'
    return
  endif
  " search() のマッチ先頭 ([) にそのまま止める
endfunction

function! yurii_pkm#get_link_under_cursor() abort
  let l:line   = getline('.')
  let l:cursor = col('.') - 1
  let l:start  = 0
  while 1
    let l:m = matchstrpos(l:line, s:link_pat, l:start)
    if len(l:m) < 3 || l:m[1] < 0
      return {}
    endif
    if l:cursor >= l:m[1] && l:cursor < l:m[2]
      let l:parts = matchlist(l:m[0], '\v\[([^\]]+)\]\(([^)]*)\)')
      return {
            \ 'raw':      l:m[0],
            \ 'text':     get(l:parts, 1, ''),
            \ 'target':   get(l:parts, 2, ''),
            \ 'startcol': l:m[1] + 1,
            \ 'endcol':   l:m[2]
            \ }
    endif
    " カーソルがリンクより後ろかチェック
    " [xxx](yyy) の形式で、リンク終端の直後にいる場合
    if l:cursor >= l:m[2]
      let l:after = strpart(l:line, l:m[2])
      " 直後がスペース2つ以上 + テキスト の形式
      if l:after =~# '^\s\{2,}\S'
        " 次のリンクが始まる前の範囲内にカーソルがあるか確認
        let l:next = matchstrpos(l:line, s:link_pat, l:m[2])
        let l:title_end = (len(l:next) >= 3 && l:next[1] >= 0) ? l:next[1] : len(l:line)
        if l:cursor < l:title_end
          let l:parts = matchlist(l:m[0], '\v\[([^\]]+)\]\(([^)]*)\)')
          return {
                \ 'raw':      l:m[0],
                \ 'text':     get(l:parts, 1, ''),
                \ 'target':   get(l:parts, 2, ''),
                \ 'startcol': l:m[1] + 1,
                \ 'endcol':   l:title_end
                \ }
        endif
      endif
    endif
    let l:start = l:m[2]
  endwhile
endfunction

function! yurii_pkm#resolve_link(target, ...) abort
  let l:base = a:0 ? a:1 : expand('%:p:h')
  if a:target =~# '^/'
    return fnamemodify(a:target, ':p')
  endif
  return fnamemodify(l:base . '/' . a:target, ':p')
endfunction

function! s:clipboard_text() abort
  let l:cb = @+
  if empty(l:cb)
    let l:cb = @"
  endif
  return trim(l:cb)
endfunction

function! s:extract_target(raw) abort
  let l:raw = trim(a:raw)
  if empty(l:raw)
    return ''
  endif
  let l:m = matchlist(l:raw, '^\[[^]]\+\](\([^)]\+\))')
  if !empty(l:m)
    return trim(l:m[1])
  endif
  return l:raw
endfunction

function! s:extract_targets_from_clipboard(text) abort
  let l:targets = []
  let l:seen = {}

  if empty(trim(a:text))
    return l:targets
  endif

  " まず Markdown リンクを全文から全部拾う
  let l:start = 0
  while 1
    let l:m = matchstrpos(a:text, '\v\[[^\]]+\]\(([^)]*)\)', l:start)
    if empty(l:m) || l:m[1] < 0
      break
    endif
    let l:raw = get(l:m, 0, '')
    let l:target = s:extract_target(l:raw)
    if !empty(l:target) && !has_key(l:seen, l:target)
      let l:seen[l:target] = 1
      call add(l:targets, l:target)
    endif
    let l:start = l:m[2]
  endwhile

  " Markdown リンクが無ければ、各行をそのままターゲットとして扱う
  if empty(l:targets)
    for l:raw in split(a:text, "\n")
      let l:target = s:extract_target(l:raw)
      if !empty(l:target) && !has_key(l:seen, l:target)
        let l:seen[l:target] = 1
        call add(l:targets, l:target)
      endif
    endfor
  endif

  return l:targets
endfunction

function! s:existing_title_for_target(target) abort
  let l:path = yurii_pkm#resolve_link(a:target)
  if filereadable(l:path) && s:is_markdown_target(a:target)
    return s:get_title(l:path)
  endif
  return ''
endfunction

function! s:link_from_target(target) abort
  let l:target = trim(a:target)
  if empty(l:target)
    return ''
  endif
  let l:name = fnamemodify(l:target, ':t')
  " md は YAML/H1 タイトルをリンク文字列にする。非mdは拡張子ごとのファイル名
  let l:title = s:existing_title_for_target(l:target)
  if s:is_markdown_target(l:target)
    let l:text = empty(l:title) ? fnamemodify(l:name, ':r') : l:title
  else
    let l:text = l:name
  endif
  return '[' . l:text . '](' . l:target . ')'
endfunction

function! s:insert_link_below_cursor(link) abort
  if empty(a:link)
    return 0
  endif
  call append(line('.'), a:link)
  return 1
endfunction

function! s:link_already_present_in_branch(link) abort
  let l:branch = s:find_section_line('branch')
  if l:branch <= 0
    return 0
  endif
  let l:end = s:branch_end_line()
  for l:i in range(l:branch + 1, l:end)
    if getline(l:i) ==# a:link
      return 1
    endif
  endfor
  return 0
endfunction

" ---------------------------------------------------------------------------
" History (Back key)
" ---------------------------------------------------------------------------

function! yurii_pkm#push_history() abort
  let l:file = yurii_pkm#current_file()
  if empty(l:file) | return | endif
  call add(g:yurii_pkm_history, {'file': l:file, 'pos': getpos('.')})
  if len(g:yurii_pkm_history) > g:yurii_pkm_history_max
    call remove(g:yurii_pkm_history, 0)
  endif
endfunction

function! yurii_pkm#open_link_under_cursor() abort
  let l:link = yurii_pkm#get_link_under_cursor()
  if empty(l:link) || empty(l:link.target)
    echo 'No link under cursor'
    return
  endif
  let l:path = yurii_pkm#resolve_link(l:link.target)
  if !filereadable(l:path) && !isdirectory(l:path)
    echo 'Link target not found: ' . l:path
    return
  endif
  let l:source_name = expand('%:t')
  let l:from_back = s:in_back_section(line('.'))
  if &modified | silent write | endif
  call yurii_pkm#push_history()
  silent! execute 'edit ' . fnameescape(l:path)
  if l:from_back
    let l:pos = s:find_reciprocal_link_pos(l:path, l:source_name)
    if get(l:pos, 0, 0) > 0
      call cursor(l:pos[0], l:pos[1])
    endif
  endif
endfunction


function! yurii_pkm#go_back() abort
  if !exists('g:yurii_pkm_history') || empty(g:yurii_pkm_history)
    echo 'History is empty'
    return
  endif
  let l:item = remove(g:yurii_pkm_history, -1)
  if &modified | silent write | endif
  silent! execute 'edit ' . fnameescape(l:item.file)
  call setpos('.', l:item.pos)
endfunction

" ---------------------------------------------------------------------------
" Note template
" ---------------------------------------------------------------------------

function! yurii_pkm#timestamp_filename() abort
  return strftime('%y%m%d%H%M%S')
endfunction

function! yurii_pkm#timestamp_yaml() abort
  return strftime('%Y-%m-%d %H:%M:%S')
endfunction

function! yurii_pkm#note_template(title, ...) abort
  let l:filetype = a:0 >= 1 ? a:1 : ''
  let l:header = [
        \ '---',
        \ 'time: ' . yurii_pkm#timestamp_yaml(),
        \ 'title: ' . a:title,
        \ ]
  if !empty(l:filetype)
    call add(l:header, 'filetype: ' . toupper(l:filetype))
  endif
  call add(l:header, '---')
  return l:header + [
        \ '',
        \ '# ' . a:title,
        \ '',
        \ '',
        \ '',
        \ '# Back',
        \ '[Index](index.md)',
        \ ]
endfunction


function! yurii_pkm#make_link(path, title) abort
  let l:file = fnamemodify(a:path, ':t')
  let l:text = empty(a:title) ? fnamemodify(l:file, ':r') : a:title
  return '[' . l:text . '](' . l:file . ')'
endfunction

" ---------------------------------------------------------------------------
" Update link titles in current buffer (Vim-side, lightweight)
" ---------------------------------------------------------------------------

function! yurii_pkm#update_current_buffer() abort
  let l:in_branch = 0
  let l:in_back   = 0
  let l:after_sep = 0
  let l:in_fence  = 0
  let l:modified  = 0

  for l:i in range(1, line('$'))
    let l:line = getline(l:i)
    let l:trimmed = trim(l:line)

    if l:trimmed =~# '^```'
      let l:in_fence = !l:in_fence
    endif

    if !l:in_fence
      if s:is_section_header_text(l:trimmed, 'branch')
        let l:in_branch = 1 | let l:in_back = 0 | let l:after_sep = 0
        continue
      endif
      if s:is_section_header_text(l:trimmed, 'back')
        let l:in_branch = 0 | let l:in_back = 1 | let l:after_sep = 0
        continue
      endif
      if l:trimmed =~# '^_\{3,}\s*$'
        let l:after_sep = 1
        continue
      endif
    endif

    if l:after_sep || l:in_fence
      continue
    endif

    if (l:in_branch || l:in_back) && l:line =~# '\[[^\]]\+\]([^)]\+\.md)'
      let l:lm = matchlist(l:line, '\(\[[^\]]\+\](\([^)]\+\))\)')
      if !empty(l:lm)
        let l:link_part = l:lm[1]
        let l:target    = trim(l:lm[2])
        let l:filepath  = expand('%:p:h') . s:sep() . l:target
        if filereadable(l:filepath)
          let l:title = s:get_title(l:filepath)
          if !empty(l:title)
            let l:new_line = '[' . l:title . '](' . l:target . ')'
            if l:new_line !=# l:line
              call setline(l:i, l:new_line)
              let l:modified = 1
            endif
          endif
        endif
      endif
    endif
  endfor

  if l:modified
    echo 'yurii_PKM: link titles updated'
  endif
endfunction

" ---------------------------------------------------------------------------
" UpdateMD / UpdateAll
" ---------------------------------------------------------------------------

function! yurii_pkm#update_md(arg) abort
  let l:root = empty(a:arg) ? yurii_pkm#ensure_root_and_index() : fnamemodify(expand(a:arg), ':p')
  if empty(l:root)
    return
  endif
  if !empty(a:arg)
    let g:yurii_pkm_root = l:root
    if !isdirectory(l:root)
      call mkdir(l:root, 'p')
    endif
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
  endif
  call yurii_pkm#check_missing_prefix_in_current_dir()
  let l:out = s:run_sync([g:yurii_pkm_python, 'update', l:root])
  if v:shell_error
    echoerr substitute(l:out, '\n\+$', '', '')
    return
  endif
  echo substitute(l:out, '\n\+$', '', '')
  call s:reload_current()
endfunction

function! yurii_pkm#update_all(arg) abort
  call yurii_pkm#update_md(a:arg)
endfunction

" 現在バッファをディスクから再読み込み（未変更の場合のみ、カーソル位置保持）
function! s:reload_current() abort
  set autoread
  if has('timers')
    " timer 経由で少し遅らせることで、job完了直後でも確実に反映される
    call timer_start(120, function('s:reload_timer_cb'))
  else
    call s:do_reload()
  endif
endfunction

function! s:reload_timer_cb(timer) abort
  call s:do_reload()
endfunction

function! s:do_reload() abort
  " 全バッファの外部変更を検出
  checktime
  " 現在バッファが未保存でなければ再読み込み（カーソル位置保持）
  let l:cur = expand('%:p')
  if !empty(l:cur) && filereadable(l:cur) && !&modified
    let l:pos = getpos('.')
    let l:view = winsaveview()
    " E823（undoファイル不一致）を抑制しつつ再読み込み
    silent! execute 'edit ' . fnameescape(l:cur)
    call winrestview(l:view)
    call setpos('.', l:pos)
  endif
endfunction

" ---------------------------------------------------------------------------
" Auto-sync: BufWritePost で update_one を非同期実行
"
"   - 保存後に動くので編集を妨げない
"   - job_start が使えれば完全非同期、なければ system() でフォールバック
"   - 完了後 checktime で Vim バッファを更新
" ---------------------------------------------------------------------------

function! yurii_pkm#autosync_on_save() abort
  if !filereadable(g:yurii_pkm_python)
    return
  endif

  " PKM root 配下のファイルのみ対象
  let l:file = expand('%:p')
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    return
  endif
  if l:file !~# '^' . escape(l:root, '/\')
    return
  endif

  let l:py   = s:python_cmd()
  let l:args = [l:py, g:yurii_pkm_python, 'update_one', l:file, l:root]

  if has('job') && has('channel')
    " 非同期実行
    let l:cmd = join(map(copy(l:args), 'shellescape(v:val)'), ' ')
    call job_start(['/bin/sh', '-c', l:cmd], {
          \ 'exit_cb': function('s:autosync_done'),
          \ 'out_io':  'null',
          \ 'err_io':  'null',
          \ })
  else
    " 同期フォールバック
    let l:cmd = join(map(copy(l:args), 'shellescape(v:val)'), ' ')
    let l:out = system(l:cmd)
    if !v:shell_error
      checktime
    endif
  endif
endfunction

function! s:autosync_done(job, status) abort
  " job完了後にバッファを外部変更に合わせる
  call s:reload_current()
endfunction

" 任意のファイルパスに対して update_one を起動するヘルパー
function! s:run_update_one_for(target_fp) abort
  if !g:yurii_pkm_autosync | return | endif
  if !filereadable(g:yurii_pkm_python) | return | endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    return
  endif
  let l:py   = s:python_cmd()
  let l:cmd  = l:py . ' ' . shellescape(g:yurii_pkm_python)
        \     . ' update_one ' . shellescape(a:target_fp)
        \     . ' ' . shellescape(l:root)
  if has('job') && has('channel')
    call job_start(['/bin/sh', '-c', l:cmd], {
          \ 'exit_cb': function('s:update_one_done', [a:target_fp]),
          \ 'out_io':  'null',
          \ 'err_io':  'null',
          \ })
  else
    call system(l:cmd)
    checktime
  endif
endfunction

function! s:update_one_done(target_fp, job, status) abort
  if expand('%:p') ==# a:target_fp
    call s:reload_current()
  else
    checktime
  endif
endfunction

" タイトル変更時は、参照元ノートのリンクタイトルも即時更新する
function! s:run_update_all_for_title_change() abort
  if !filereadable(g:yurii_pkm_python)
    return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    return
  endif

  let l:py  = s:python_cmd()
  let l:cmd = l:py . ' ' . shellescape(g:yurii_pkm_python)
        \    . ' update ' . shellescape(l:root)

  if has('job') && has('channel')
    call job_start(['/bin/sh', '-c', l:cmd], {
          \ 'exit_cb': function('s:title_change_update_done'),
          \ 'out_io':  'null',
          \ 'err_io':  'null',
          \ })
  else
    call system(l:cmd)
    checktime
  endif
endfunction

function! s:title_change_update_done(job, status) abort
  call s:reload_current()
endfunction

" ---------------------------------------------------------------------------
" rename_title (:NT)
" ---------------------------------------------------------------------------

function! yurii_pkm#rename_title_with_default(default) abort
  let l:title = input('new title: ', a:default)

  if empty(l:title)
    echo 'Cancelled'
    return
  endif

  let l:lines = getline(1, '$')
  let l:yaml_start = -1
  let l:yaml_end   = -1
  for l:i in range(len(l:lines))
    if l:lines[l:i] ==# '---'
      if l:yaml_start < 0
        let l:yaml_start = l:i
      else
        let l:yaml_end = l:i
        break
      endif
    endif
  endfor

  if l:yaml_start == 0 && l:yaml_end > 0
    let l:done = 0
    for l:i in range(l:yaml_start + 1, l:yaml_end - 1)
      if l:lines[l:i] =~# '^title:\s*'
        let l:lines[l:i] = 'title: ' . l:title
        let l:done = 1
        break
      endif
    endfor
    if !l:done
      call insert(l:lines, 'title: ' . l:title, l:yaml_start + 1)
    endif
  else
    let l:header = ['---', 'time: ' . yurii_pkm#timestamp_yaml(),
          \ 'title: ' . l:title, '---', '']
    let l:lines = l:header + l:lines
  endif

  " H1 も更新
  let l:found_h1 = 0
  for l:i in range(len(l:lines))
    if l:lines[l:i] =~# '^#\s\+'
      let l:lines[l:i] = '# ' . l:title
      let l:found_h1 = 1
      break
    endif
  endfor
  if !l:found_h1
    call add(l:lines, '# ' . l:title)
  endif

  call setline(1, l:lines)
  if len(l:lines) < line('$')
    execute (len(l:lines) + 1) . ',$delete _'
  endif
  write
  call yurii_pkm#clear_title_cache()
  call s:run_update_all_for_title_change()
endfunction

function! yurii_pkm#rename_title(args) abort
  let l:default = a:args ==# '' ? yurii_pkm#current_title() : a:args
  call yurii_pkm#rename_title_with_default(l:default)
endfunction

" ---------------------------------------------------------------------------
" create_note (internal)
" ---------------------------------------------------------------------------

function! yurii_pkm#create_note(prefix, title, open_after, insert_mode) abort
  let l:root = yurii_pkm#ensure_root_and_index()
  if empty(l:root)
    return {}
  endif
  let l:fname = a:prefix . '_' . yurii_pkm#timestamp_filename() . '.md'
  let l:file  = l:root . s:sep() . l:fname
  if filereadable(l:file)
    echoerr 'File already exists: ' . l:file
    return {}
  endif

  let l:parent_file  = expand('%:p')
  let l:parent_title = yurii_pkm#current_title()

  let l:tmpl = yurii_pkm#note_template(a:title, a:prefix)
  if filereadable(l:parent_file)
    let l:parent_link = yurii_pkm#make_link(l:parent_file, l:parent_title)
    call insert(l:tmpl, l:parent_link, len(l:tmpl) - 1)
  endif
  call writefile(l:tmpl, l:file)

  let l:link = yurii_pkm#make_link(l:file, a:title)
  let l:save_ai = &autoindent
  let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  if a:insert_mode ==# 'branch'
    let l:ins = s:branch_end_line()
    call append(l:ins, l:link)
    silent write
  elseif a:insert_mode ==# 'cursor'
    call append(line('.'), l:link)
    silent write
  endif
  let &autoindent = l:save_ai
  let &smartindent = l:save_si

  if a:open_after
    call yurii_pkm#push_history()
    execute 'edit ' . fnameescape(l:file)
    let &autoindent = l:save_ai
    let &smartindent = l:save_si
    call cursor(8, 1)
    startinsert
  endif

  return {'path': l:file, 'link': l:link}
endfunction


" ---------------------------------------------------------------------------
" :NC - New Child (常に C プレフィックス、タイトルのみ入力)
" ---------------------------------------------------------------------------

function! yurii_pkm#new_child(args) abort
  try
    let l:title = input('title: ', a:args)
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return
  endtry
  if empty(l:title)
    let l:title = yurii_pkm#timestamp_filename()
  endif
  call yurii_pkm#create_note('C', l:title, 1, 'branch')
endfunction

" ---------------------------------------------------------------------------
" :NF / :NA - 現在ファイルと同ディレクトリに F_ / A_ ノートを作成し
"             現在ファイルの 本文末尾に追加する
" ---------------------------------------------------------------------------

function! yurii_pkm#new_here_typed(prefix) abort
  try
    let l:title = input('title: ')
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return
  endtry
  if empty(l:title)
    let l:title = yurii_pkm#timestamp_filename()
  endif
  call yurii_pkm#create_note(a:prefix, l:title, 1, 'branch')
endfunction

" ---------------------------------------------------------------------------
" タイトル入力なし、h/o/b選択あり (nf / nn / nk 共通内部実装)
" ---------------------------------------------------------------------------

function! s:new_note_no_title(prefix) abort
  let l:parent_line  = line('.')
  let l:parent_file  = expand('%:t')
  let l:parent_title = yurii_pkm#current_title()

  echon 'mode: (O)rphan (H)ere (B)ack Enter=body-end: '
  let l:char = getchar()
  redraw

  " Esc or Ctrl-C でキャンセル
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:mode = nr2char(l:char)

  let l:insert_at_cursor = 0
  let l:no_parent_link   = 0
  let l:reverse_link     = 0

  if l:mode =~? '^o$'
    let l:no_parent_link = 1
  elseif l:mode =~? '^h$'
    let l:insert_at_cursor = 1
  elseif l:mode =~? '^b$'
    let l:reverse_link = 1
  endif

  let l:title = yurii_pkm#timestamp_filename()
  let l:filetype = toupper(a:prefix)
  let l:no_prefix_name = (l:filetype ==# 'N' || l:filetype ==# 'K')
  let l:fname = l:no_prefix_name ? (l:title . '.md') : (a:prefix . '_' . l:title . '.md')
  let l:dir   = expand('%:p:h')
  let l:file  = l:dir . s:sep() . l:fname
  let l:link  = yurii_pkm#make_link(l:fname, l:title)

  if !l:no_parent_link && !l:reverse_link
    let l:save_ai = &autoindent
    let l:save_si = &smartindent
    setlocal noautoindent nosmartindent
    if l:insert_at_cursor
      call append(l:parent_line, l:link)
    else
      let l:ins = s:branch_end_line()
      call append(l:ins, l:link)
    endif
    let &autoindent = l:save_ai
    let &smartindent = l:save_si
    silent noautocmd write
    call s:run_update_one_for(expand('%:p'))
  endif

  let l:parent_link_line = yurii_pkm#make_link(l:parent_file, l:parent_title)
  let l:is_k = (a:prefix ==? 'K')

  if l:reverse_link
    if l:is_k
      " nk b モード: リンクあり、空行なし
      " # title / (空) / [リンク] / Back / [index]
      let l:content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ 'filetype: ' . l:filetype,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ '# Back',
            \ l:parent_link_line,
            \ '[Index](index.md)' ]
      let l:cursor_line = 8
    else
      " nn/nf b モード: リンク後に空行あり
      " # title / (空) / [リンク] / (空) / Back / [index]
      let l:content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ 'filetype: ' . l:filetype,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ '# Back',
            \ l:parent_link_line,
            \ '',
            \ '[Index](index.md)' ]
      let l:cursor_line = 8
    endif
  elseif l:is_k
    " nk の h/Enter/o モード: 空行1つ、body なし
    " # title / (空) / Back / [index]
    let l:content = [
          \ '---',
          \ 'time: ' . yurii_pkm#timestamp_yaml(),
          \ 'title: ' . l:title,
          \ 'filetype: ' . l:filetype,
          \ '---',
          \ '',
          \ '# ' . l:title,
          \ '',
          \ '# Back',
          \ '[Index](index.md)' ]
    let l:cursor_line = 7
  else
    " nn/nf の h/Enter/o モード: 従来どおり
    let l:content = [
          \ '---',
          \ 'time: ' . yurii_pkm#timestamp_yaml(),
          \ 'title: ' . l:title,
          \ 'filetype: ' . l:filetype,
          \ '---',
          \ '',
          \ '# ' . l:title,
          \ '',
          \ '',
          \ '' ]
    call add(l:content, '# Back')
    if !l:no_parent_link
      call add(l:content, l:parent_link_line)
    endif
    call add(l:content, '[Index](index.md)')
    let l:cursor_line = 8
  endif

  call writefile(l:content, l:file)

  " bモード: 親ファイルの Back セクション直後に新ノートへのリンクを追記してsync
  if l:reverse_link
    " ディスクとバッファの不一致を防ぐため先に保存
    if &modified
      silent noautocmd write
    endif
    let l:new_link = yurii_pkm#make_link(l:fname, l:title)
    let l:parent_fp = l:dir . s:sep() . l:parent_file
    if filereadable(l:parent_fp)
      let l:plines = readfile(l:parent_fp)
      let l:back_idx = -1
      for l:i in range(0, len(l:plines) - 1)
        if s:is_section_header_text(l:plines[l:i], 'back')
          let l:back_idx = l:i
          break
        endif
      endfor
      if index(l:plines, l:new_link) < 0
        if l:back_idx < 0
          " Back セクションがなければ末尾に追加
          call add(l:plines, '')
          call add(l:plines, '# Back')
          call add(l:plines, '[Index](index.md)')
          let l:back_idx = len(l:plines) - 2
        endif
        " Back 行の直後（back_idx + 1）に挿入
        call insert(l:plines, l:new_link, l:back_idx + 1)
        call writefile(l:plines, l:parent_fp)
        call s:run_update_one_for(l:parent_fp)
      endif
    endif
  endif

  if &modified
    try
      silent noautocmd write
    catch
      echohl ErrorMsg
      echom 'Error: could not save current buffer; new note was created but not opened: ' . l:fname
      echohl None
      return
    endtry
  endif

  call yurii_pkm#push_history()
  execute 'edit ' . fnameescape(l:file)
  call cursor(l:cursor_line, 1)
  startinsert
endfunction

" ---------------------------------------------------------------------------
" ビジュアル選択範囲を新ノートに切り出す (nn / nf / nk のビジュアル版)
"
" 動作:
"   - 選択範囲のテキストを取得して削除（元ファイルから cut）
"   - 新ノートファイルに YAML + # title + 空行 + 切り出しテキスト を書き込む
"   - bモードのときは選択テキストの代わりにリンクだけ残す（本文なし）
"   - 画面（カーソル位置・スクロール）は元のまま動かさない
" ---------------------------------------------------------------------------

function! s:visual_new_note(prefix, mode) abort
  " ビジュアル選択の範囲を取得（'< と '> マーク）
  let l:vstart = line("'<")
  let l:vend   = line("'>")
  if l:vstart <= 0 || l:vend <= 0 || l:vstart > l:vend
    echo 'No visual selection'
    return
  endif

  let l:sel_lines = getline(l:vstart, l:vend)

  let l:parent_file  = expand('%:t')
  let l:parent_title = yurii_pkm#current_title()
  let l:dir          = expand('%:p:h')

  let l:title = yurii_pkm#timestamp_filename()
  let l:filetype = toupper(a:prefix)
  let l:no_prefix_name = (l:filetype ==# 'N' || l:filetype ==# 'K')
  let l:fname = l:no_prefix_name ? (l:title . '.md') : (a:prefix . '_' . l:title . '.md')
  let l:file  = l:dir . s:sep() . l:fname
  let l:parent_link_line = yurii_pkm#make_link(l:parent_file, l:parent_title)
  let l:link_to_new      = yurii_pkm#make_link(l:fname, l:title)

  let l:is_b = (a:mode ==? 'b')
  let l:is_k = (a:prefix ==? 'K')

  " 新ファイルの内容を組み立てる
  if l:is_b
    " bモード: 選択テキストは新ファイルに移す、Back セクションに親リンク
    if l:is_k
      let l:content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ 'filetype: ' . l:filetype,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ '# Back',
            \ l:parent_link_line,
            \ '[Index](index.md)' ]
    else
      let l:content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ 'filetype: ' . l:filetype,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ '# Back',
            \ l:parent_link_line,
            \ '',
            \ '[Index](index.md)' ]
    endif
    " 選択テキストを本文（Back の直前）に挿入
    let l:back_idx = s:find_section_index_in_lines(l:content, 'back')
    " Back の前に空行 + 選択テキストを差し込む
    let l:insert_pos = l:back_idx
    call extend(l:content, l:sel_lines, l:insert_pos)
  else
    " h / o / Enter モード: 本文に選択テキストを配置
    let l:content = [
          \ '---',
          \ 'time: ' . yurii_pkm#timestamp_yaml(),
          \ 'title: ' . l:title,
          \ 'filetype: ' . l:filetype,
          \ '---',
          \ '',
          \ '# ' . l:title,
          \ '' ]
    call extend(l:content, l:sel_lines)
    call add(l:content, '')
    call add(l:content, '# Back')
    call add(l:content, l:parent_link_line)
    call add(l:content, '[Index](index.md)')
  endif

  call writefile(l:content, l:file)

  " ---- 元ファイルの選択範囲を置き換える ----
  " スクロール位置・カーソルを保存
  let l:save_view = winsaveview()
  let l:save_pos  = getpos('.')

  let l:save_ai = &autoindent
  let l:save_si = &smartindent
  setlocal noautoindent nosmartindent

  " 選択範囲をリンク1行に置き換える（全モード共通）
  execute l:vstart . ',' . l:vend . 'delete _'
  call append(l:vstart - 1, l:link_to_new)
  " カーソルはリンク行の次行（元の選択終端の次）
  let l:cursor_line = l:vstart + 1

  if l:is_b
    " bモード: 親の Back セクション直後にも逆リンクを追記
    let l:parent_fp = l:dir . s:sep() . l:parent_file
    if filereadable(l:parent_fp)
      let l:plines = readfile(l:parent_fp)
      let l:back_idx2 = -1
      for l:i in range(0, len(l:plines) - 1)
        if s:is_section_header_text(l:plines[l:i], 'back')
          let l:back_idx2 = l:i
          break
        endif
      endfor
      if index(l:plines, l:link_to_new) < 0
        if l:back_idx2 < 0
          call add(l:plines, '')
          call add(l:plines, '# Back')
          call add(l:plines, '[Index](index.md)')
          let l:back_idx2 = len(l:plines) - 2
        endif
        call insert(l:plines, l:link_to_new, l:back_idx2 + 1)
        call writefile(l:plines, l:parent_fp)
        call s:run_update_one_for(l:parent_fp)
      endif
    endif
  endif

  let &autoindent = l:save_ai
  let &smartindent = l:save_si

  " スクロール位置は保持、カーソルはリンク行の次行へ
  call winrestview(l:save_view)
  let l:cursor_line = min([l:cursor_line, line('$')])
  call cursor(l:cursor_line, 1)

  silent noautocmd write
  call s:run_update_one_for(expand('%:p'))

  redraw | echon 'Created: ' . l:fname
endfunction

" ビジュアル選択から nf / nn / nk を呼ぶエントリポイント
function! yurii_pkm#visual_new_quick_no_title() abort
  echo 'prefix (a-z): '
  let l:char = getchar()
  redraw
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:ch = nr2char(l:char)
  if l:ch !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  call s:visual_select_mode(toupper(l:ch))
endfunction

function! yurii_pkm#visual_new_prefix_note(prefix) abort
  call s:visual_select_mode(a:prefix)
endfunction

function! s:visual_select_mode(prefix) abort
  echon 'mode: (O)rphan (H)ere (B)ack Enter=body-end: '
  let l:char = getchar()
  redraw
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:mode = nr2char(l:char)
  call s:visual_new_note(a:prefix, l:mode)
endfunction

" nf用: prefix入力 → h/o/b選択
function! yurii_pkm#new_quick_no_title() abort
  echo 'prefix (a-z): '
  let l:char = getchar()
  redraw
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:ch = nr2char(l:char)
  if l:ch !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  call s:new_note_no_title(toupper(l:ch))
endfunction

" nn / nk用: prefix固定 → h/o/b選択
function! yurii_pkm#new_prefix_note(prefix) abort
  call s:new_note_no_title(a:prefix)
endfunction

" ---------------------------------------------------------------------------
" :NQ - Quick new child (旧 QuickNewChildWithMode に忠実)
"   1. プレフィックス1文字入力（即時確定）
"   2. タイトル入力
"   3. モード選択: (O)rphan / (H)ere / (B)ack / Enter=branch
" ---------------------------------------------------------------------------

function! yurii_pkm#new_quick(args) abort
  let l:parent_bufnr = bufnr('%')
  let l:parent_line = line('.')
  let l:parent_file  = expand('%:t')
  let l:parent_title = yurii_pkm#current_title()

  echo 'prefix (a-z): '
  let l:raw = getchar()
  redraw
  if l:raw == 27 || l:raw == 3
    echo 'Cancelled'
    return
  endif
  let l:char = nr2char(l:raw)
  if l:char !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  let l:prefix = toupper(l:char)

  let l:title = input('title: ', a:args)

  echon "\nmode: (O)rphan (H)ere (B)ack Enter=body-end: "
  let l:raw2 = getchar()
  redraw
  if l:raw2 == 27 || l:raw2 == 3
    echo 'Cancelled'
    return
  endif
  let l:mode = nr2char(l:raw2)

  let l:insert_at_cursor = 0
  let l:no_parent_link   = 0
  let l:reverse_link     = 0

  if l:mode =~? '^o$'
    let l:no_parent_link = 1
  elseif l:mode =~? '^h$'
    let l:insert_at_cursor = 1
  elseif l:mode =~? '^b$'
    let l:reverse_link = 1
  endif

  if empty(l:title)
    let l:title = yurii_pkm#timestamp_filename()
  endif

  let l:fname = l:prefix . '_' . yurii_pkm#timestamp_filename() . '.md'
  let l:dir   = expand('%:p:h')
  let l:file  = l:dir . s:sep() . l:fname
  let l:link = yurii_pkm#make_link(l:fname, l:title)

  if !l:no_parent_link && !l:reverse_link
    let l:save_ai = &autoindent
    let l:save_si = &smartindent
    setlocal noautoindent nosmartindent
    if l:insert_at_cursor
      call append(l:parent_line, l:link)
    else
      let l:ins = s:branch_end_line()
      call append(l:ins, l:link)
    endif
    let &autoindent = l:save_ai
    let &smartindent = l:save_si
    silent noautocmd write
    call s:run_update_one_for(expand('%:p'))
  endif

  let l:parent_link_line = yurii_pkm#make_link(l:parent_file, l:parent_title)
  let l:is_k = (l:prefix ==? 'K')

  if l:reverse_link
    if l:is_k
      let l:content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ l:parent_link_line,
            \ '# Back',
            \ '[Index](index.md)' ]
      let l:cursor_line = 8
    else
      let l:content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ l:parent_link_line,
            \ '',
            \ '# Back',
            \ '[Index](index.md)' ]
      let l:cursor_line = 8
    endif
  elseif l:is_k
    let l:content = [
          \ '---',
          \ 'time: ' . yurii_pkm#timestamp_yaml(),
          \ 'title: ' . l:title,
          \ '---',
          \ '',
          \ '# ' . l:title,
          \ '',
          \ '# Back',
          \ '[Index](index.md)' ]
    let l:cursor_line = 7
  else
    let l:content = [
          \ '---',
          \ 'time: ' . yurii_pkm#timestamp_yaml(),
          \ 'title: ' . l:title,
          \ '---',
          \ '',
          \ '# ' . l:title,
          \ '',
          \ '',
          \ '' ]
    call add(l:content, '# Back')
    if !l:no_parent_link
      call add(l:content, l:parent_link_line)
    endif
    call add(l:content, '[Index](index.md)')
    let l:cursor_line = 8
  endif

  call writefile(l:content, l:file)

  " bモード: 親ファイルの Back セクション直後に新ノートへのリンクを追記してsync
  if l:reverse_link
    " ディスクとバッファの不一致を防ぐため先に保存
    if &modified
      silent noautocmd write
    endif
    let l:new_link = yurii_pkm#make_link(l:fname, l:title)
    let l:parent_fp = l:dir . s:sep() . l:parent_file
    if filereadable(l:parent_fp)
      let l:plines = readfile(l:parent_fp)
      let l:back_idx = -1
      for l:i in range(0, len(l:plines) - 1)
        if s:is_section_header_text(l:plines[l:i], 'back')
          let l:back_idx = l:i
          break
        endif
      endfor
      if index(l:plines, l:new_link) < 0
        if l:back_idx < 0
          call add(l:plines, '')
          call add(l:plines, '# Back')
          call add(l:plines, '[Index](index.md)')
          let l:back_idx = len(l:plines) - 2
        endif
        call insert(l:plines, l:new_link, l:back_idx + 1)
        call writefile(l:plines, l:parent_fp)
        call s:run_update_one_for(l:parent_fp)
      endif
    endif
  endif

  if &modified
    try
      silent noautocmd write
    catch
      echohl ErrorMsg
      echom 'Error: could not save current buffer; new note was created but not opened: ' . l:fname
      echohl None
      return
    endtry
  endif

  call yurii_pkm#push_history()
  execute 'edit ' . fnameescape(l:file)
  call cursor(l:cursor_line, 1)
  startinsert
endfunction


" ---------------------------------------------------------------------------
" :CA - Create Atomic note (本文末尾に追加、新ファイルを開く)
" ---------------------------------------------------------------------------

function! yurii_pkm#create_atomic(args) abort
  let l:prefix = g:yurii_pkm_default_atomic_prefix
  let l:prefix = toupper(input('prefix [' . l:prefix . ']: ', l:prefix))
  if empty(l:prefix) | let l:prefix = g:yurii_pkm_default_atomic_prefix | endif
  let l:title = input('title: ', a:args)
  if empty(l:title) | echo 'Cancelled' | return | endif
  call yurii_pkm#create_note(l:prefix, l:title, 1, 'branch')
endfunction


" ---------------------------------------------------------------------------
" :BC - Add from clipboard before Back
" ---------------------------------------------------------------------------

function! yurii_pkm#add_from_clipboard(...) abort
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:insert_at_cursor = 0
  for l:arg in a:000
    if l:arg ==# 'here'
      let l:insert_at_cursor = 1
    endif
  endfor

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    let l:path = yurii_pkm#resolve_link(l:target)
    if !filereadable(l:path)
      echo 'Warning: not found: ' . l:target
      continue
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  if l:insert_at_cursor
    let l:ins = line('.')
    for l:lk in reverse(copy(l:links))
      call append(l:ins, l:lk)
    endfor
  else
    let l:ins = s:branch_end_line()
    if l:ins <= 0
      echo 'Error: back section not found'
      return
    endif
    for l:lk in l:links
      call append(l:ins, l:lk)
      let l:ins += 1
    endfor
  endif
  silent write
  echo 'Added ' . len(l:links) . ' link(s)'
endfunction

function! yurii_pkm#paste_clipboard_link_here() abort
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    " md ファイルは存在チェックあり、非md（.svc 等）は存在チェックなしでリンク化
    if s:is_markdown_target(l:target)
      let l:path = yurii_pkm#resolve_link(l:target)
      if !filereadable(l:path)
        echo 'Warning: not found: ' . l:target
        continue
      endif
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  let l:ins = line('.')
  for l:lk in reverse(copy(l:links))
    call append(l:ins, l:lk)
  endfor
  silent write
endfunction

function! yurii_pkm#add_clipboard_to_branch() abort
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    let l:path = yurii_pkm#resolve_link(l:target)
    if !filereadable(l:path)
      echo 'Warning: not found: ' . l:target
      continue
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  let l:ins = s:branch_end_line()
  if l:ins <= 0
    echo 'Error: back section not found'
    return
  endif
  for l:lk in l:links
    call append(l:ins, l:lk)
    let l:ins += 1
  endfor
  silent write
endfunction

function! yurii_pkm#linkify_filename_under_cursor() abort
  let l:word = expand('<cfile>')
  if empty(l:word)
    echo 'Error: no filename under cursor'
    return
  endif
  let l:path = yurii_pkm#resolve_link(l:word)
  if !filereadable(l:path)
    echo 'Error: not found: ' . l:word
    return
  endif
  let l:link = s:link_from_target(l:word)
  if empty(l:link)
    echo 'Error: failed to build link'
    return
  endif
  let l:line = getline('.')
  let l:start = col('.')
  let l:idx = match(l:line, '\V' . escape(l:word, '\'))
  if l:idx < 0
    echo 'Error: filename text not found on line'
    return
  endif
  let l:newline = strpart(l:line, 0, l:idx) . l:link . strpart(l:line, l:idx + strlen(l:word))
  call setline('.', l:newline)
endfunction

" ---------------------------------------------------------------------------
" :YN - Yank Note name
" ---------------------------------------------------------------------------
" ---------------------------------------------------------------------------
" :YN - Yank Note name (拡張子なし)
" ---------------------------------------------------------------------------

function! yurii_pkm#yank_name() abort
  let l:name = expand('%:t')
  let @+ = l:name
  let @" = l:name
  echo 'Yanked: ' . l:name
endfunction

" ---------------------------------------------------------------------------
" gp helper: システムクリップボード優先で、末尾改行を落として行下に追加
" ---------------------------------------------------------------------------

function! yurii_pkm#paste_charwise() abort
  let l:text = @+
  if empty(l:text)
    let l:text = @"
  endif
  " 末尾の改行を除去してキャラクター単位に変換
  let l:text = substitute(l:text, '\n\+$', '', '')
  let l:lines = split(l:text, "\n", 1)
  call append(line('.'), l:lines)
endfunction

" ---------------------------------------------------------------------------
" :AT2 - Add To clipboard target (逆リンク)
" ---------------------------------------------------------------------------

function! yurii_pkm#at_add() abort
  let l:current_file  = expand('%:t')
  let l:current_title = yurii_pkm#current_title()

  let l:cb = s:clipboard_text()
  if empty(l:cb)
    echo 'Error: clipboard empty'
    return
  endif

  let l:targets = s:extract_targets_from_clipboard(l:cb)
  if empty(l:targets)
    echo 'Error: no valid link target in clipboard'
    return
  endif

  let l:new_link = yurii_pkm#make_link(l:current_file, l:current_title)

  let l:added = 0
  let l:already = 0
  let l:missing = 0

  for l:target in l:targets
    let l:target_fp = yurii_pkm#resolve_link(l:target)
    if !filereadable(l:target_fp)
      let l:missing += 1
      echom 'Warning: not found: ' . l:target
      continue
    endif
    if fnamemodify(l:target_fp, ':t') ==# 'index.md'
      continue
    endif

    let l:lines = readfile(l:target_fp)
    let l:back_idx = len(l:lines)
    let l:found_back = 0
    for l:i in range(0, len(l:lines) - 1)
      if s:is_section_header_text(l:lines[l:i], 'back')
        let l:back_idx = l:i
        let l:found_back = 1
        break
      endif
    endfor

    let l:search_end = l:back_idx - 1
    if l:search_end >= 0 && index(l:lines[0 : l:search_end], l:new_link) >= 0
      let l:already += 1
      continue
    endif

    if !l:found_back
      call add(l:lines, '')
      call add(l:lines, '# Back')
      call add(l:lines, '[Index](index.md)')
      let l:back_idx = len(l:lines) - 2
    endif

    call insert(l:lines, l:new_link, l:back_idx)
    call writefile(l:lines, l:target_fp)
    call s:run_update_one_for(l:target_fp)
    let l:added += 1
  endfor

  echo 'AT: added ' . l:added . ', already ' . l:already . ', missing ' . l:missing
endfunction


" ---------------------------------------------------------------------------
" SortYomi (branch セクション yomi ソート) - Python 経由
" ---------------------------------------------------------------------------

function! yurii_pkm#open_index() abort
  let l:root = yurii_pkm#ensure_root_and_index()
  if empty(l:root)
    return
  endif
  execute 'cd ' . fnameescape(l:root)
  let l:index = s:index_path(l:root)
  if filereadable(l:index)
    if s:consume_index_created_flag()
      call s:open_index_with_delay(l:index)
    else
      call yurii_pkm#push_history()
      execute 'edit ' . fnameescape(l:index)
    endif
  else
    echo 'index.md not found in ' . l:root
  endif
endfunction

function! yurii_pkm#sort_yomi() abort
  " sort_yomi.py が同ディレクトリにあれば呼び出す
  let l:py_dir = fnamemodify(g:yurii_pkm_python, ':h')
  let l:sort_script = l:py_dir . s:sep() . 'sort_yomi.py'
  if !filereadable(l:sort_script)
    echohl ErrorMsg
    echo 'sort_yomi.py not found at: ' . l:sort_script
    echohl None
    return
  endif
  if &modified | write | endif
  let l:result = system(s:python_cmd() . ' ' . shellescape(l:sort_script) .
        \ ' ' . shellescape(expand('%:p')))
  echo l:result
  edit!
endfunction

" ---------------------------------------------------------------------------
" :RP - Rename Prefix
"   現在のファイルのプレフィクスを変更し、PKMルート配下の全リンクを更新する
" ---------------------------------------------------------------------------

function! yurii_pkm#rename_prefix() abort
  let l:lines = getline(1, '$')
  let l:cur_type = ''
  let l:yaml_start = -1
  let l:yaml_end = -1
  for l:i in range(0, len(l:lines) - 1)
    if l:lines[l:i] ==# '---'
      if l:yaml_start < 0
        let l:yaml_start = l:i
      else
        let l:yaml_end = l:i
        break
      endif
    endif
  endfor
  if l:yaml_start == 0 && l:yaml_end > 0
    for l:i in range(l:yaml_start + 1, l:yaml_end - 1)
      if l:lines[l:i] =~? '^filetype:\s*'
        let l:cur_type = toupper(trim(substitute(l:lines[l:i], '^filetype:\s*', '', 'i')))
        break
      endif
    endfor
  endif
  if empty(l:cur_type)
    let l:cur_type = 'N'
  endif

  " 新プレフィクスを1文字即時入力
  echon 'filetype [' . l:cur_type . '] → '
  let l:char = nr2char(getchar())
  redraw
  if l:char !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  let l:new_type = toupper(l:char)
  if l:new_type ==# l:cur_type
    echo 'Filetype unchanged'
    return
  endif

  " 未保存の変更があれば保存
  if l:yaml_start == 0 && l:yaml_end > 0
    let l:done = 0
    for l:i in range(l:yaml_start + 1, l:yaml_end - 1)
      if l:lines[l:i] =~? '^filetype:\s*'
        let l:lines[l:i] = 'filetype: ' . l:new_type
        let l:done = 1
        break
      endif
    endfor
    if !l:done
      call insert(l:lines, 'filetype: ' . l:new_type, l:yaml_start + 1)
    endif
  else
    call insert(l:lines, '---', 0)
    call insert(l:lines, 'filetype: ' . l:new_type, 1)
    call insert(l:lines, '---', 2)
  endif
  call setline(1, l:lines)
  if len(l:lines) < line('$')
    execute (len(l:lines) + 1) . ',$delete _'
  endif
  silent write
  echo 'Filetype changed: ' . l:cur_type . ' → ' . l:new_type
endfunction



function! yurii_pkm#expand_s_under_cursor(...) abort
  let l:source_path = expand('%:p')
  if empty(l:source_path) || !filereadable(l:source_path)
    echoerr 'expand_s: current file is not readable'
    return
  endif

  let l:depth_arg = a:0 ? trim(a:1) : ''
  if empty(l:depth_arg)
    let l:depth = get(g:, 'yurii_pkm_expand_default_depth', 1)
  else
    let l:depth = str2nr(l:depth_arg)
  endif
  if l:depth < 0
    echoerr 'expand_s: depth must be >= 0'
    return
  endif

  let l:expand_py = g:yurii_pkm_expand_s_python
  if !filereadable(l:expand_py)
    echoerr 'expand_s.py not found: ' . l:expand_py
    return
  endif

  let l:root = yurii_pkm#ensure_root_and_index()
  if empty(l:root)
    return
  endif

  let l:py  = s:python_cmd()
  let l:cmd = l:py . ' ' . shellescape(l:expand_py)
        \ . ' expand_any ' . shellescape(l:source_path)
        \ . ' ' . shellescape(l:root)
        \ . ' ' . shellescape(string(l:depth))

  let l:out = system(l:cmd)
  if v:shell_error
    echoerr 'expand_s error: ' . substitute(l:out, '\n\+$', '', '')
    return
  endif

  let l:t_path = substitute(l:out, '\n\+$', '', '')
  if !filereadable(l:t_path)
    echoerr 'expand_s: T note not created: ' . l:t_path
    return
  endif

  let l:t_fname = fnamemodify(l:t_path, ':t')
  let l:t_title = s:get_title(l:t_path)
  let l:t_link  = yurii_pkm#make_link(l:t_fname, l:t_title)

  call append(line('$'), ['', l:t_link])
  silent write
  execute 'edit ' . fnameescape(l:t_path)

  echo 'Expanded: ' . l:t_fname . ' (depth=' . l:depth . ')'
endfunction


" ---------------------------------------------------------------------------
" Markdown table helpers (vimwiki-like)
" ---------------------------------------------------------------------------

function! s:is_table_line(line) abort
  return a:line =~# '\v^\s*\|.*\|\s*$'
endfunction

function! s:is_table_separator(line) abort
  return a:line =~# '\v^\s*\|\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|\s*$'
endfunction

function! s:table_block_range(lnum) abort
  if a:lnum < 1 || a:lnum > line('$') || !s:is_table_line(getline(a:lnum))
    return [0, 0]
  endif
  let l:start = a:lnum
  while l:start > 1 && s:is_table_line(getline(l:start - 1))
    let l:start -= 1
  endwhile
  let l:end = a:lnum
  while l:end < line('$') && s:is_table_line(getline(l:end + 1))
    let l:end += 1
  endwhile
  return [l:start, l:end]
endfunction

function! s:parse_table_line(line) abort
  let l:indent = matchstr(a:line, '^\s*')
  let l:core = substitute(a:line, '^\s*|\s*', '', '')
  let l:core = substitute(l:core, '\s*|\s*$', '', '')
  let l:cells = split(l:core, '|', 1)
  call map(l:cells, 'trim(v:val)')
  if empty(l:cells)
    let l:cells = ['']
  endif
  return {
        \ 'indent': l:indent,
        \ 'cells': l:cells,
        \ 'sep': s:is_table_separator(a:line)
        \ }
endfunction

function! s:table_col_count(start_lnum, end_lnum) abort
  let l:max_cols = 0
  for l:lnum in range(a:start_lnum, a:end_lnum)
    let l:parsed = s:parse_table_line(getline(l:lnum))
    let l:max_cols = max([l:max_cols, len(l:parsed.cells)])
  endfor
  return l:max_cols
endfunction

function! s:table_separator_token(width, align) abort
  let l:w = max([3, a:width])
  if a:align ==# 'right'
    return repeat('-', l:w - 1) . ':'
  elseif a:align ==# 'center'
    return ':' . repeat('-', max([1, l:w - 2])) . ':'
  elseif a:align ==# 'left'
    return ':' . repeat('-', l:w - 1)
  endif
  return repeat('-', l:w)
endfunction

function! s:table_align_block(start_lnum, end_lnum) abort
  let [l:new_lines, l:cols] = s:table_align_lines(getline(a:start_lnum, a:end_lnum))
  if l:cols <= 0
    return 0
  endif
  call setline(a:start_lnum, l:new_lines)
  return l:cols
endfunction

function! s:table_pipe_positions(line) abort
  let l:positions = []
  let l:start = 0
  while 1
    let l:idx = stridx(a:line, '|', l:start)
    if l:idx < 0
      break
    endif
    call add(l:positions, l:idx)
    let l:start = l:idx + 1
  endwhile
  return l:positions
endfunction

function! s:table_cell_index_from_col(line, colnum) abort
  let l:pipes = s:table_pipe_positions(a:line)
  if len(l:pipes) < 2
    return 1
  endif
  let l:cur = max([0, a:colnum - 1])
  for l:i in range(0, len(l:pipes) - 2)
    if l:cur <= l:pipes[l:i + 1]
      return l:i + 1
    endif
  endfor
  return len(l:pipes) - 1
endfunction

function! s:table_cell_startcol(line, cell_index) abort
  let l:pipes = s:table_pipe_positions(a:line)
  if len(l:pipes) < a:cell_index + 1 || a:cell_index < 1
    return 1
  endif
  let l:start0 = l:pipes[a:cell_index - 1] + 2
  if l:start0 > l:pipes[a:cell_index]
    let l:start0 = l:pipes[a:cell_index - 1] + 1
  endif
  return l:start0 + 1
endfunction

function! s:table_blank_row(cols, indent) abort
  return a:indent . '|' . join(repeat(['   '], a:cols), '|') . '|'
endfunction

function! s:table_headers(start_lnum, end_lnum, cols) abort
  let l:headers = []
  if a:start_lnum < a:end_lnum && s:is_table_separator(getline(a:start_lnum + 1))
    let l:parsed = s:parse_table_line(getline(a:start_lnum))
    while len(l:parsed.cells) < a:cols
      call add(l:parsed.cells, '')
    endwhile
    for l:i in range(0, a:cols - 1)
      let l:label = trim(l:parsed.cells[l:i])
      call add(l:headers, empty(l:label) ? ('Col ' . (l:i + 1)) : l:label)
    endfor
    return l:headers
  endif

  for l:i in range(1, a:cols)
    call add(l:headers, 'Col ' . l:i)
  endfor
  return l:headers
endfunction

function! s:table_align_lines(lines) abort
  if empty(a:lines)
    return [[], 0]
  endif

  let l:cols = 0
  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    let l:cols = max([l:cols, len(l:parsed.cells)])
  endfor
  if l:cols <= 0
    return [copy(a:lines), 0]
  endif

  let l:widths = repeat([3], l:cols)
  let l:aligns = repeat(['plain'], l:cols)

  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    while len(l:parsed.cells) < l:cols
      call add(l:parsed.cells, '')
    endwhile

    if l:parsed.sep
      for l:i in range(0, l:cols - 1)
        let l:token = trim(l:parsed.cells[l:i])
        if l:token =~# '^:-\+$'
          let l:aligns[l:i] = 'left'
        elseif l:token =~# '^:-\+:$'
          let l:aligns[l:i] = 'center'
        elseif l:token =~# '^\-\+:$'
          let l:aligns[l:i] = 'right'
        endif
        let l:plain = substitute(l:token, ':', '', 'g')
        let l:widths[l:i] = max([l:widths[l:i], strdisplaywidth(l:plain)])
      endfor
    else
      for l:i in range(0, l:cols - 1)
        let l:widths[l:i] = max([l:widths[l:i], strdisplaywidth(l:parsed.cells[l:i])])
      endfor
    endif
  endfor

  let l:new_lines = []
  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    while len(l:parsed.cells) < l:cols
      call add(l:parsed.cells, '')
    endwhile

    let l:parts = []
    for l:i in range(0, l:cols - 1)
      if l:parsed.sep
        let l:token = s:table_separator_token(l:widths[l:i], l:aligns[l:i])
        call add(l:parts, ' ' . l:token . ' ')
      else
        let l:cell = l:parsed.cells[l:i]
        let l:pad = l:widths[l:i] - strdisplaywidth(l:cell)
        call add(l:parts, ' ' . l:cell . repeat(' ', l:pad) . ' ')
      endif
    endfor
    call add(l:new_lines, l:parsed.indent . '|' . join(l:parts, '|') . '|')
  endfor

  return [l:new_lines, l:cols]
endfunction

function! s:find_prev_table_data_line(start_lnum, first_lnum) abort
  let l:lnum = a:start_lnum
  while l:lnum >= a:first_lnum
    if s:is_table_line(getline(l:lnum)) && !s:is_table_separator(getline(l:lnum))
      return l:lnum
    endif
    let l:lnum -= 1
  endwhile
  return 0
endfunction

function! s:find_next_table_data_line(start_lnum, last_lnum) abort
  let l:lnum = a:start_lnum
  while l:lnum <= a:last_lnum
    if s:is_table_line(getline(l:lnum)) && !s:is_table_separator(getline(l:lnum))
      return l:lnum
    endif
    let l:lnum += 1
  endwhile
  return 0
endfunction

function! yurii_pkm#table_align_current() abort
  let [l:start, l:end] = s:table_block_range(line('.'))
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  call s:table_align_block(l:start, l:end)
endfunction

function! yurii_pkm#table_new(args) abort
  let l:cols = 3
  let l:body_rows = 1
  let l:parts = split(trim(a:args))
  if len(l:parts) >= 1 && l:parts[0] =~# '^\d\+$'
    let l:cols = max([1, str2nr(l:parts[0])])
  endif
  if len(l:parts) >= 2 && l:parts[1] =~# '^\d\+$'
    let l:body_rows = max([1, str2nr(l:parts[1])])
  endif

  let l:indent = matchstr(getline('.'), '^\s*')
  let l:table_lines = [
        \ l:indent . '|' . join(repeat(['   '], l:cols), '|') . '|',
        \ l:indent . '|' . join(repeat([' --- '], l:cols), '|') . '|'
        \ ]
  for l:_ in range(1, l:body_rows)
    call add(l:table_lines, l:indent . '|' . join(repeat(['   '], l:cols), '|') . '|')
  endfor

  let l:start_lnum = line('.')
  if empty(trim(getline('.')))
    " 空行を削除してからテーブルを挿入（setline+リストは以降の行を上書きするためNG）
    call deletebufline('%', l:start_lnum)
    call append(l:start_lnum - 1, l:table_lines)
  else
    call append(l:start_lnum, l:table_lines)
    let l:start_lnum += 1
  endif

  let l:end_lnum = l:start_lnum + len(l:table_lines) - 1
  call s:table_align_block(l:start_lnum, l:end_lnum)
  call cursor(l:start_lnum, s:table_cell_startcol(getline(l:start_lnum), 1))
  startinsert
endfunction


function! s:feedkeys_insert(keys) abort
  call feedkeys("\<C-g>u" . a:keys, 'in')
endfunction

function! yurii_pkm#table_tab_action() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    call s:feedkeys_insert("\<Tab>")
    return
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    call s:feedkeys_insert("\<Tab>")
    return
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:parsed = s:parse_table_line(l:cur_line)
  let l:cols = len(l:parsed.cells)
  if l:cols <= 0
    call s:feedkeys_insert("\<Tab>")
    return
  endif

  if l:cur_cell < l:cols
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell + 1))
    return
  endif

  let l:next_data = s:find_next_table_data_line(l:cur_lnum + 1, l:end)
  if l:next_data > 0
    call cursor(l:next_data, s:table_cell_startcol(getline(l:next_data), 1))
    return
  endif

  let l:insert_after = l:cur_lnum
  if l:insert_after < l:end && s:is_table_separator(getline(l:insert_after + 1))
    let l:insert_after += 1
  endif
  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), 1))
endfunction

function! yurii_pkm#table_stab_action() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    call s:feedkeys_insert("\<C-d>")
    return
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    call s:feedkeys_insert("\<C-d>")
    return
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:parsed = s:parse_table_line(l:cur_line)
  let l:cols = len(l:parsed.cells)
  if l:cols <= 0
    return
  endif

  if l:cur_cell > 1
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell - 1))
    return
  endif

  let l:prev_data = s:find_prev_table_data_line(l:cur_lnum - 1, l:start)
  if l:prev_data > 0
    call cursor(l:prev_data, s:table_cell_startcol(getline(l:prev_data), l:cols))
  endif
endfunction

function! yurii_pkm#table_cr_action() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    call s:feedkeys_insert("\<CR>")
    return
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    call s:feedkeys_insert("\<CR>")
    return
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:parsed = s:parse_table_line(l:cur_line)
  let l:cols = len(l:parsed.cells)
  if l:cols <= 0
    call s:feedkeys_insert("\<CR>")
    return
  endif

  let l:target_cell = min([max([1, l:cur_cell]), l:cols])
  let l:next_data = s:find_next_table_data_line(l:cur_lnum + 1, l:end)
  if l:next_data > 0
    call cursor(l:next_data, s:table_cell_startcol(getline(l:next_data), l:target_cell))
    return
  endif

  let l:insert_after = l:cur_lnum
  if l:cur_lnum < l:end && s:is_table_separator(getline(l:cur_lnum + 1))
    let l:insert_after = l:cur_lnum + 1
  endif

  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), l:target_cell))
endfunction
function! yurii_pkm#table_tab() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return "\<Tab>"
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    return "\<Tab>"
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:cols = s:table_align_block(l:start, l:end)
  if l:cols <= 0
    return "\<Tab>"
  endif

  if l:cur_cell < l:cols
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell + 1))
    return ''
  endif

  let l:next_data = s:find_next_table_data_line(l:cur_lnum + 1, l:end)
  if l:next_data > 0
    call cursor(l:next_data, s:table_cell_startcol(getline(l:next_data), 1))
    return ''
  endif

  let l:insert_after = l:cur_lnum
  if l:insert_after < l:end && s:is_table_separator(getline(l:insert_after + 1))
    let l:insert_after += 1
  endif
  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), 1))
  return ''
endfunction

function! yurii_pkm#table_stab() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return "\<S-Tab>"
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    return "\<S-Tab>"
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:cols = s:table_align_block(l:start, l:end)
  if l:cols <= 0
    return "\<S-Tab>"
  endif

  if l:cur_cell > 1
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell - 1))
    return ''
  endif

  let l:prev_data = s:find_prev_table_data_line(l:cur_lnum - 1, l:start)
  if l:prev_data > 0
    call cursor(l:prev_data, s:table_cell_startcol(getline(l:prev_data), l:cols))
    return ''
  endif
  return ''
endfunction

function! yurii_pkm#table_cr() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return "\<CR>"
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    return "\<CR>"
  endif

  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:cols = s:table_align_block(l:start, l:end)
  if l:cols <= 0
    return "\<CR>"
  endif

  let l:insert_after = l:cur_lnum
  if s:is_table_separator(getline(l:cur_lnum))
    let l:insert_after = l:cur_lnum
  elseif l:cur_lnum < l:end && s:is_table_separator(getline(l:cur_lnum + 1))
    let l:insert_after = l:cur_lnum + 1
  endif

  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), 1))
  return ''
endfunction

function! s:table_row_editor_lines(headers, cells) abort
  let l:lines = [
        \ '# TableRowEdit: 各項目の次の行を書き換えて :write で反映',
        \ '# q で閉じる / ZZ で保存して閉じる',
        \ ''
        \ ]
  for l:i in range(0, len(a:cells) - 1)
    call add(l:lines, '[' . (l:i + 1) . '] ' . a:headers[l:i])
    call add(l:lines, a:cells[l:i])
    call add(l:lines, '')
  endfor
  return l:lines
endfunction

function! yurii_pkm#table_row_edit() abort
  let l:cur_lnum = line('.')
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  if s:is_table_separator(getline(l:cur_lnum))
    echo 'Separator row cannot be edited here'
    return
  endif

  let l:cols = s:table_align_block(l:start, l:end)
  let l:parsed = s:parse_table_line(getline(l:cur_lnum))
  while len(l:parsed.cells) < l:cols
    call add(l:parsed.cells, '')
  endwhile
  let l:headers = s:table_headers(l:start, l:end, l:cols)

  let l:origin_win = win_getid()
  vertical botright new
  let l:editor_buf = bufnr('%')
  call setline(1, s:table_row_editor_lines(l:headers, l:parsed.cells))

  let b:yurii_table_editor = 1
  let b:yurii_table_src_bufnr = bufnr('#') > 0 ? bufnr('#') : bufnr(winbufnr(l:origin_win))
  let b:yurii_table_src_bufnr = winbufnr(l:origin_win)
  let b:yurii_table_src_lnum = l:cur_lnum
  let b:yurii_table_src_start = l:start
  let b:yurii_table_src_end = l:end
  let b:yurii_table_cols = l:cols
  let b:yurii_table_headers = copy(l:headers)

  setlocal buftype=acwrite
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=markdown
  setlocal wrap
  setlocal linebreak
  setlocal breakindent
  setlocal nonumber
  setlocal norelativenumber
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal textwidth=0
  setlocal modifiable

  execute 'autocmd! BufWriteCmd <buffer> call yurii_pkm#table_row_editor_apply()'
  nnoremap <silent><buffer> q  <Cmd>bd!<CR>
  nnoremap <silent><buffer> ZZ <Cmd>write<Bar>bd!<CR>

  call cursor(4, 1)
endfunction

function! yurii_pkm#table_row_editor_apply() abort
  if !exists('b:yurii_table_editor') || !b:yurii_table_editor
    return
  endif

  let l:cols = get(b:, 'yurii_table_cols', 0)
  let l:headers = get(b:, 'yurii_table_headers', [])
  if l:cols <= 0 || len(l:headers) != l:cols
    echoerr 'TableRowEdit: invalid editor state'
    return
  endif

  let l:new_cells = []
  let l:base = 4
  for l:i in range(0, l:cols - 1)
    let l:value_lnum = l:base + (l:i * 3) + 1
    call add(l:new_cells, trim(getline(l:value_lnum)))
  endfor

  let l:src_buf = b:yurii_table_src_bufnr
  let l:src_start = b:yurii_table_src_start
  let l:src_end = b:yurii_table_src_end
  let l:src_lnum = b:yurii_table_src_lnum

  if !bufexists(l:src_buf)
    echoerr 'TableRowEdit: source buffer not found'
    return
  endif

  let l:block_lines = getbufline(l:src_buf, l:src_start, l:src_end)
  if empty(l:block_lines)
    echoerr 'TableRowEdit: source table not found'
    return
  endif

  let l:row_idx = l:src_lnum - l:src_start
  if l:row_idx < 0 || l:row_idx >= len(l:block_lines)
    echoerr 'TableRowEdit: source row is out of range'
    return
  endif

  let l:src_parsed = s:parse_table_line(l:block_lines[l:row_idx])
  let l:block_lines[l:row_idx] = l:src_parsed.indent . '| ' . join(l:new_cells, ' | ') . ' |'

  let [l:aligned, l:cols2] = s:table_align_lines(l:block_lines)
  if l:cols2 <= 0
    echoerr 'TableRowEdit: failed to align table'
    return
  endif

  call setbufline(l:src_buf, l:src_start, l:aligned)
  setlocal nomodified
  echo 'Table row updated'
endfunction


function! s:csv_escape_field(field) abort
  let l:field = a:field
  let l:needs_quote = l:field =~# '[",\n]'
  let l:field = substitute(l:field, '"', '""', 'g')
  return l:needs_quote ? '"' . l:field . '"' : l:field
endfunction

function! s:csv_join_fields(fields) abort
  let l:out = []
  for l:field in a:fields
    call add(l:out, s:csv_escape_field(l:field))
  endfor
  return join(l:out, ',')
endfunction

function! s:csv_parse_line(line) abort
  let l:fields = []
  let l:field = ''
  let l:in_quotes = 0
  let l:i = 0
  while l:i < strlen(a:line)
    let l:ch = strpart(a:line, l:i, 1)
    if l:in_quotes
      if l:ch ==# '"'
        if l:i + 1 < strlen(a:line) && strpart(a:line, l:i + 1, 1) ==# '"'
          let l:field .= '"'
          let l:i += 1
        else
          let l:in_quotes = 0
        endif
      else
        let l:field .= l:ch
      endif
    else
      if l:ch ==# ','
        call add(l:fields, l:field)
        let l:field = ''
      elseif l:ch ==# '"'
        let l:in_quotes = 1
      else
        let l:field .= l:ch
      endif
    endif
    let l:i += 1
  endwhile
  call add(l:fields, l:field)
  return l:fields
endfunction

function! s:csv_block_range(lnum) abort
  if a:lnum < 1 || a:lnum > line('$') || empty(trim(getline(a:lnum)))
    return [0, 0]
  endif
  let l:start = a:lnum
  let l:end = a:lnum
  while l:start > 1 && !empty(trim(getline(l:start - 1)))
    let l:start -= 1
  endwhile
  while l:end < line('$') && !empty(trim(getline(l:end + 1)))
    let l:end += 1
  endwhile
  return [l:start, l:end]
endfunction

function! s:table_lines_to_csv(lines) abort
  let l:csv = []
  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    if l:parsed.sep
      continue
    endif
    call add(l:csv, s:csv_join_fields(l:parsed.cells))
  endfor
  return l:csv
endfunction

function! s:csv_lines_to_table(lines, indent) abort
  let l:rows = []
  let l:maxcols = 0
  for l:line in a:lines
    if empty(trim(l:line))
      continue
    endif
    let l:fields = s:csv_parse_line(l:line)
    let l:maxcols = max([l:maxcols, len(l:fields)])
    call add(l:rows, l:fields)
  endfor
  if empty(l:rows)
    return []
  endif
  let l:maxcols = max([1, l:maxcols])
  let l:table = []
  for l:ridx in range(0, len(l:rows) - 1)
    while len(l:rows[l:ridx]) < l:maxcols
      call add(l:rows[l:ridx], '')
    endwhile
    call add(l:table, a:indent . '| ' . join(l:rows[l:ridx], ' | ') . ' |')
    if l:ridx == 0
      call add(l:table, a:indent . '|' . join(repeat([' --- '], l:maxcols), '|') . '|')
    endif
  endfor
  let [l:aligned, l:cols] = s:table_align_lines(l:table)
  return l:aligned
endfunction

function! s:append_current_file_branch_link(link) abort
  let l:ins = s:branch_end_line()
  if l:ins <= 0
    return 0
  endif
  let l:save_ai = &l:autoindent
  let l:save_si = &l:smartindent
  setlocal noautoindent nosmartindent
  call append(l:ins, a:link)
  let &l:autoindent = l:save_ai
  let &l:smartindent = l:save_si
  return 1
endfunction

function! s:next_t_csv_path(base_dir, idx_hint) abort
  let l:ts = strftime('%y%m%d%H%M%S')
  let l:idx = a:idx_hint > 0 ? a:idx_hint : 1
  let l:path = a:base_dir . '/T_' . l:ts . '_' . l:idx . '.csv'
  while filereadable(l:path)
    let l:idx += 1
    let l:path = a:base_dir . '/T_' . l:ts . '_' . l:idx . '.csv'
  endwhile
  return l:path
endfunction

function! s:csv_branch_link(csv_path) abort
  let l:name = fnamemodify(a:csv_path, ':t')
  return '[' . fnamemodify(l:name, ':r') . '](' . l:name . ')'
endfunction

function! yurii_pkm#csv_new() abort
  let l:src_name = expand('%:p')
  let l:base_dir = empty(l:src_name) ? getcwd() : fnamemodify(l:src_name, ':p:h')
  let l:csv_path = s:next_t_csv_path(l:base_dir, 1)
  call writefile([], l:csv_path)
  call s:append_current_file_branch_link(s:csv_branch_link(l:csv_path))
  silent! write
  execute 'edit ' . fnameescape(l:csv_path)
endfunction

function! yurii_pkm#table_to_csv() abort
  let [l:start, l:end] = s:table_block_range(line('.'))
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  let l:src_name = expand('%:p')
  let l:base_dir = empty(l:src_name) ? getcwd() : fnamemodify(l:src_name, ':p:h')
  let l:csv_lines = s:table_lines_to_csv(getline(l:start, l:end))
  let l:csv_path = s:next_t_csv_path(l:base_dir, l:start)
  call writefile(l:csv_lines, l:csv_path)
  call deletebufline('%', l:start, l:end)
  call s:append_current_file_branch_link(s:csv_branch_link(l:csv_path))
  silent! write
  execute 'edit ' . fnameescape(l:csv_path)
endfunction

function! yurii_pkm#csv_to_table() abort
  return yurii_pkm#csv_to_table_current()
endfunction

function! yurii_pkm#table_to_csv_current() abort
  let [l:start, l:end] = s:table_block_range(line('.'))
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  let l:csv = s:table_lines_to_csv(getline(l:start, l:end))
  call setline(l:start, l:csv)
  if l:end > l:start + len(l:csv) - 1
    execute (l:start + len(l:csv)) . ',' . l:end . 'delete _'
  endif
  echo 'Converted table to CSV'
endfunction

function! yurii_pkm#csv_to_table_current() abort
  let [l:start, l:end] = s:csv_block_range(line('.'))
  if l:start == 0
    echo 'Not on CSV lines'
    return
  endif
  let l:indent = matchstr(getline(l:start), '^\s*')
  let l:table = s:csv_lines_to_table(getline(l:start, l:end), l:indent)
  if empty(l:table)
    echo 'CSV block is empty'
    return
  endif
  call setline(l:start, l:table)
  if l:end > l:start + len(l:table) - 1
    execute (l:start + len(l:table)) . ',' . l:end . 'delete _'
  endif
  echo 'Converted CSV to table'
endfunction

function! s:table_csv_temp_path(src_buf, start) abort
  let l:src_name = bufname(a:src_buf)
  let l:base_dir = empty(l:src_name) ? getcwd() : fnamemodify(l:src_name, ':p:h')
  let l:stamp = strftime('%y%m%d%H%M%S')
  return l:base_dir . '/T_' . l:stamp . '_' . a:start . '.csv'
endfunction

function! s:table_csv_apply_to_source(csv_lines, src_buf, src_start, src_end, indent) abort
  if a:src_buf < 0 || a:src_start <= 0 || a:src_end < a:src_start || !bufexists(a:src_buf)
    echoerr 'TableCsvEdit: source buffer not found'
    return 0
  endif

  call bufload(a:src_buf)

  let l:table = s:csv_lines_to_table(a:csv_lines, a:indent)
  if empty(l:table)
    echoerr 'TableCsvEdit: CSV is empty'
    return 0
  endif

  call setbufline(a:src_buf, a:src_start, l:table)
  let l:new_end = a:src_start + len(l:table) - 1
  if a:src_end > l:new_end
    call deletebufline(a:src_buf, l:new_end + 1, a:src_end)
  endif
  call setbufvar(a:src_buf, '&modified', 1)
  return l:new_end
endfunction


function! yurii_pkm#table_csv_editor_cleanup(...) abort
  return
endfunction

function! yurii_pkm#table_csv_edit() abort
  let l:cur_lnum = line('.')
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  if l:start == 0
    echo 'Not on a table'
    return
  endif

  let l:src_buf = bufnr('%')
  let l:src_indent = matchstr(getline(l:start), '^\s*')
  let l:csv_lines = s:table_lines_to_csv(getline(l:start, l:end))
  let l:csv_path = s:table_csv_temp_path(l:src_buf, l:start)
  call writefile(l:csv_lines, l:csv_path)

  execute 'edit ' . fnameescape(l:csv_path)

  let b:yurii_table_csv_editor = 1
  let b:yurii_table_src_bufnr = l:src_buf
  let b:yurii_table_src_start = l:start
  let b:yurii_table_src_end = l:end
  let b:yurii_table_src_indent = l:src_indent
  let b:yurii_table_csv_path = l:csv_path

  setlocal filetype=csv
  setlocal nowrap
  setlocal nonumber
  setlocal norelativenumber
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal textwidth=0

  augroup yurii_table_csv_editor
    autocmd! * <buffer>
  augroup END
  nnoremap <silent><buffer> q  <Cmd>bd!<CR>
  echo 'TableCsvEdit: editing ' . fnamemodify(l:csv_path, ':t') . ' (use :TableCsvApplySaved to apply)'
endfunction

function! yurii_pkm#table_csv_editor_apply(...) abort
  if a:0 >= 1
    let l:buf = a:1
  else
    let l:buf = bufnr('%')
    " カレントバッファがCSVエディタでなければ、全バッファから探す
    if !getbufvar(l:buf, 'yurii_table_csv_editor', 0)
      let l:buf = -1
      for l:b in range(1, bufnr('$'))
        if bufexists(l:b) && getbufvar(l:b, 'yurii_table_csv_editor', 0)
          let l:buf = l:b
          break
        endif
      endfor
    endif
  endif
  if l:buf < 0 || !getbufvar(l:buf, 'yurii_table_csv_editor', 0)
    echoerr 'TableCsvEdit: not a TableCsvEdit CSV buffer'
    return
  endif

  let l:src_buf = getbufvar(l:buf, 'yurii_table_src_bufnr', -1)
  let l:src_start = getbufvar(l:buf, 'yurii_table_src_start', 0)
  let l:src_end = getbufvar(l:buf, 'yurii_table_src_end', 0)
  let l:indent = getbufvar(l:buf, 'yurii_table_src_indent', '')
  let l:src_win = bufwinid(l:src_buf)

  if bufloaded(l:buf)
    let l:csv_lines = getbufline(l:buf, 1, '$')
  else
    let l:csv_path = getbufvar(l:buf, 'yurii_table_csv_path', bufname(l:buf))
    if empty(l:csv_path) || !filereadable(l:csv_path)
      echoerr 'TableCsvEdit: CSV file not found'
      return
    endif
    let l:csv_lines = readfile(l:csv_path)
  endif

  let l:new_end = s:table_csv_apply_to_source(l:csv_lines, l:src_buf, l:src_start, l:src_end, l:indent)
  if l:new_end <= 0
    return
  endif

  call setbufvar(l:buf, 'yurii_table_src_end', l:new_end)

  if l:src_win > 0
    call win_gotoid(l:src_win)
  else
    execute 'keepalt buffer ' . l:src_buf
  endif
  call cursor(l:src_start, 1)

  if bufnr('%') == l:src_buf
    silent! write
  endif

  echo 'CSV changes applied to table'
endfunction

function! yurii_pkm#table_csv_editor_apply_saved(...) abort
  let l:buf = a:0 >= 1 ? a:1 : bufnr('%')
  call yurii_pkm#table_csv_editor_apply(l:buf)
endfunction


" ---------------------------------------------------------------------------
" テーブル行・列の追加・削除
" ---------------------------------------------------------------------------

" カーソル行をテーブルから削除（ヘッダ行・セパレータ行は削除不可）
function! yurii_pkm#table_del_row() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table row'
    return
  endif
  if s:is_table_separator(getline(l:lnum))
    echo 'Cannot delete separator row'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  if l:lnum == l:start
    echo 'Cannot delete header row'
    return
  endif
  let l:data_rows = 0
  for l:i in range(l:start, l:end)
    if !s:is_table_separator(getline(l:i)) && l:i != l:start
      let l:data_rows += 1
    endif
  endfor
  if l:data_rows <= 1
    echo 'Cannot delete the last data row'
    return
  endif
  execute l:lnum . 'delete _'
  call s:table_align_block(l:start, l:end - 1)
endfunction

" カーソル列をテーブルから削除
function! yurii_pkm#table_del_col() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table column'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  let l:cols = s:table_col_count(l:start, l:end)
  if l:cols <= 1
    echo 'Cannot delete the last column'
    return
  endif
  let l:col_idx = s:table_cell_index_from_col(getline(l:lnum), col('.'))
  if l:col_idx < 0 || l:col_idx >= l:cols
    echo 'Cursor is not inside a cell'
    return
  endif
  for l:i in range(l:start, l:end)
    let l:parsed = s:parse_table_line(getline(l:i))
    if len(l:parsed.cells) <= l:col_idx
      continue
    endif
    call remove(l:parsed.cells, l:col_idx)
    if l:parsed.sep
      let l:new_cells = map(copy(l:parsed.cells), '"---"')
      call setline(l:i, l:parsed.indent . '| ' . join(l:new_cells, ' | ') . ' |')
    else
      call setline(l:i, l:parsed.indent . '| ' . join(l:parsed.cells, ' | ') . ' |')
    endif
  endfor
  call s:table_align_block(l:start, l:end)
endfunction

" カーソル行の下に空行を追加
function! yurii_pkm#table_add_row() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table row'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  let l:cols = s:table_col_count(l:start, l:end)
  let l:indent = matchstr(getline(l:start), '^\s*')
  let l:insert_after = l:lnum
  if l:insert_after < l:end && s:is_table_separator(getline(l:insert_after + 1))
    let l:insert_after += 1
  endif
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:insert_after + 1, s:table_cell_startcol(getline(l:insert_after + 1), 1))
endfunction

" カーソル列の右に空列を追加
function! yurii_pkm#table_add_col() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table column'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  let l:cols = s:table_col_count(l:start, l:end)
  let l:col_idx = s:table_cell_index_from_col(getline(l:lnum), col('.'))
  if l:col_idx < 0
    let l:col_idx = l:cols - 1
  endif
  let l:insert_at = l:col_idx + 1
  for l:i in range(l:start, l:end)
    let l:parsed = s:parse_table_line(getline(l:i))
    let l:pos = min([l:insert_at, len(l:parsed.cells)])
    if l:parsed.sep
      call insert(l:parsed.cells, '---', l:pos)
      let l:new_cells = map(copy(l:parsed.cells), '"---"')
      call setline(l:i, l:parsed.indent . '| ' . join(l:new_cells, ' | ') . ' |')
    else
      call insert(l:parsed.cells, '', l:pos)
      call setline(l:i, l:parsed.indent . '| ' . join(l:parsed.cells, ' | ') . ' |')
    endif
  endfor
  call s:table_align_block(l:start, l:end)
endfunction

" ---------------------------------------------------------------------------
" CopyStack Mode  (スタック選択コピー)
" ---------------------------------------------------------------------------
" 使い方:
"   :CopyStack  モード開始 / 2回目でコミット（クリップボードに書いて終了）
"   y           ノーマル: 現在行をスタックに追加
"               ビジュアル: 選択範囲をスタックに追加
" ---------------------------------------------------------------------------

let s:stack_copy_mode  = 0
let s:stack_copy_lines = []
let s:stack_copy_stl_save = ''
let s:stack_copy_wbr_save = ''

function! s:stack_copy_statusline_on() abort
  let s:stack_copy_stl_save = &l:statusline
  if exists('+winbar')
    let s:stack_copy_wbr_save = &l:winbar
  else
    let s:stack_copy_wbr_save = ''
  endif
  setlocal statusline=%#WarningMsg#\ [CopyStack]\ %*%f\ %m%=%l/%L
  if exists('+winbar')
    let &l:winbar = '%#WarningMsg# [CopyStack] y:追加  d:切り取り  :CopyStack:確定/終了 %#Normal#'
  endif
endfunction

function! s:stack_copy_statusline_off() abort
  if s:stack_copy_stl_save ==# ''
    setlocal statusline&
  else
    let &l:statusline = s:stack_copy_stl_save
  endif
  if exists('+winbar')
    if s:stack_copy_wbr_save ==# ''
      setlocal winbar&
    else
      let &l:winbar = s:stack_copy_wbr_save
    endif
  endif
  let s:stack_copy_stl_save = ''
  let s:stack_copy_wbr_save = ''
endfunction

function! s:stack_copy_finish(copy_to_clipboard) abort
  if a:copy_to_clipboard && !empty(s:stack_copy_lines)
    let l:text = join(s:stack_copy_lines, "\n")
    let @+ = l:text
    let @" = l:text
    
  else
    
  endif
  silent! nunmap <buffer> y
  silent! xunmap <buffer> y
  silent! nunmap <buffer> d
  silent! xunmap <buffer> d
  call s:stack_copy_statusline_off()
  let s:stack_copy_mode  = 0
  let s:stack_copy_lines = []
endfunction

function! yurii_pkm#stack_copy_toggle() abort
  if !s:stack_copy_mode
    let s:stack_copy_mode  = 1
    let s:stack_copy_lines = []
    nnoremap <buffer> <silent> <nowait> y :<C-u>call yurii_pkm#stack_copy_yank_line()<CR>
    xnoremap <buffer> <silent> <nowait> y :<C-u>call yurii_pkm#stack_copy_yank_visual()<CR>
    nnoremap <buffer> <silent> <nowait> d :<C-u>call yurii_pkm#stack_copy_delete_line()<CR>
    xnoremap <buffer> <silent> <nowait> d :<C-u>call yurii_pkm#stack_copy_delete_visual()<CR>
    call s:stack_copy_statusline_on()
    
  else
    call s:stack_copy_finish(!empty(s:stack_copy_lines))
  endif
endfunction

function! yurii_pkm#stack_copy_yank_line() abort
  let l:line = getline('.')
  call add(s:stack_copy_lines, l:line)
  
endfunction

function! yurii_pkm#stack_copy_yank_visual() abort range
  let l:s = line("'<")
  let l:e = line("'>")
  for l:i in range(l:s, l:e)
    call add(s:stack_copy_lines, getline(l:i))
  endfor
  
endfunction

function! yurii_pkm#stack_copy_delete_line() abort
  let l:line = getline('.')
  call add(s:stack_copy_lines, l:line)
  execute 'delete _'
  
endfunction

function! yurii_pkm#stack_copy_delete_visual() abort range
  let l:s = line("'<")
  let l:e = line("'>")
  for l:i in range(l:s, l:e)
    call add(s:stack_copy_lines, getline(l:i))
  endfor
  execute "normal! <Esc>"
  execute "'<,'>delete _"
  
endfunction
