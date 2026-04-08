" autoload/yurii_search.vim

function! yurii_search#run(...)
  let l:dir    = getcwd()
  let l:script = g:yurii_search_tui

  if !filereadable(l:script)
    echoerr 'fsearch_tui.py が見つかりません: ' . l:script
    return
  endif

  let l:tmpfile = tempname()
  let l:py = get(g:, 'yurii_search_python_cmd', executable('python3') ? 'python3' : 'python')
  let l:cmd = shellescape(l:py) . ' ' . shellescape(l:script)
            \ . ' ' . shellescape(l:dir)
            \ . ' ' . shellescape(l:tmpfile)

  " 端末ウィンドウとして起動、終了したら結果を読む
  let l:buf = term_start(['/bin/bash', '-c', l:cmd], {
    \ 'term_finish': 'close',
    \ 'exit_cb':     function('s:OnExit', [l:tmpfile]),
    \ 'term_rows':   40,
    \ })
endfunction

function! s:OnExit(tmpfile, job, status)
  if !filereadable(a:tmpfile)
    return
  endif
  let l:selected = trim(join(readfile(a:tmpfile), ''))
  call delete(a:tmpfile)
  if l:selected != ''
    execute 'edit ' . fnameescape(l:selected)
  endif
endfunction
