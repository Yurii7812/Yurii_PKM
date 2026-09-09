" autoload/yurii_search.vim
" ファイル単位のキーワード AND 検索。fzf があれば fzf 版、無ければ旧 TUI。

function! yurii_search#run(...) abort
  if executable('fzf')
    call s:fzf_run(a:0 > 0 ? a:1 : '')
  else
    call s:tui_run()
  endif
endfunction

" --- fzf 版 ------------------------------------------------------------------
" 各ノートを「絶対パス \t タイトル \t 本文全部」の 1 行にして fzf へ。
" --nth=2,3 でタイトル+本文に AND 一致（行またぎOK）、--with-nth=2 で一覧はタイトルのみ。
function! s:fzf_run(initial) abort
  let l:root = get(g:, 'yurii_pkm_root', '')
  if empty(l:root) || !isdirectory(l:root)
    let l:root = getcwd()
  endif
  let l:idx = expand('<sfile>:p:h:h') . '/python/notes_index.py'
  if !filereadable(l:idx)
    echoerr 'notes_index.py が見つかりません: ' . l:idx
    return
  endif
  let l:tmp = tempname()
  let l:src = 'python3 ' . shellescape(l:idx) . ' ' . shellescape(l:root)
  " alt-1..alt-9 で「今見えている N 行目」を選んで即開く（数字は普通に打てる）
  let l:jump = join(map(range(1, 9), '"alt-" . v:val . ":pos(" . v:val . ")+accept"'), ',')
  " --with-nth='2..' : 一覧・検索対象を タイトル+本文 に。path(1列目)は隠して非マッチ。
  let l:fzf = 'fzf --exact --layout=reverse --info=inline'
        \ . ' --delimiter=''\t'' --with-nth=''2..'''
        \ . ' --prompt=''note> '' --query=' . shellescape(a:initial)
        \ . ' --preview-window=right:55%:wrap'
        \ . ' --preview ' . shellescape('sed -n 1,300p -- {1}')
        \ . ' --bind ' . shellescape('ctrl-/:toggle-preview,ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up,' . l:jump)
  let l:cmd = l:src . ' | ' . l:fzf . ' > ' . shellescape(l:tmp)
  call term_start(['/bin/bash', '-c', l:cmd], {
        \ 'term_finish': 'close',
        \ 'exit_cb': function('s:fzf_done', [l:tmp]),
        \ })
endfunction

function! s:fzf_done(tmp, job, status) abort
  if !filereadable(a:tmp)
    return
  endif
  let l:line = trim(join(readfile(a:tmp), ''))
  call delete(a:tmp)
  if empty(l:line)
    return
  endif
  let l:path = split(l:line, "\t")[0]
  if filereadable(l:path)
    execute 'edit ' . fnameescape(l:path)
  endif
endfunction

" --- 旧 curses TUI（fzf が無い時のフォールバック）--------------------------
function! s:tui_run() abort
  let l:script = get(g:, 'yurii_search_tui', '')
  if !filereadable(l:script)
    echoerr 'fsearch_tui.py が見つかりません: ' . l:script
    return
  endif
  let l:tmpfile = tempname()
  let l:cmd = 'python3 ' . shellescape(l:script)
        \ . ' ' . shellescape(getcwd())
        \ . ' ' . shellescape(l:tmpfile)
  call term_start(['/bin/bash', '-c', l:cmd], {
        \ 'term_finish': 'close',
        \ 'exit_cb':     function('s:tui_done', [l:tmpfile]),
        \ })
endfunction

function! s:tui_done(tmpfile, job, status) abort
  if !filereadable(a:tmpfile)
    return
  endif
  let l:selected = trim(join(readfile(a:tmpfile), ''))
  call delete(a:tmpfile)
  if l:selected != ''
    execute 'edit ' . fnameescape(l:selected)
  endif
endfunction
