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
  let l:idx = get(g:, 'yurii_search_index', '')
  if empty(l:idx) || !filereadable(l:idx)
    echoerr 'notes_index.py が見つかりません: ' . l:idx
    return
  endif
  let l:tmp = tempname()
  let l:src = 'python3 ' . shellescape(l:idx) . ' ' . shellescape(l:root)

  " 移動モードで使うキー
  let l:mkeys = '1,2,3,4,5,6,7,8,9,j,k,g,q'
  let l:movebinds = '1:pos(1)+accept,2:pos(2)+accept,3:pos(3)+accept,4:pos(4)+accept,'
        \ . '5:pos(5)+accept,6:pos(6)+accept,7:pos(7)+accept,8:pos(8)+accept,9:pos(9)+accept,'
        \ . 'j:down,k:up,g:first,q:abort'
  " ⎋ = 移動モード（検索OFF・数字/jk有効） / / = 検索モードへ戻る
  let l:modal = 'start:unbind(' . l:mkeys . '),'
        \ . 'esc:disable-search+rebind(' . l:mkeys . ')+change-prompt(移動 › ),'
        \ . '/:enable-search+unbind(' . l:mkeys . ')+change-prompt(検索 › )'

  " ヒット箇所を色付きで（rg で該当行＋前後3行、無ければ全文）
  let l:preview = 'q={q}; f={1}; '
        \ . 'if [ -n "$q" ]; then '
        \ . 'p=$(printf "%s" "$q" | tr -s " " | tr " " "|"); '
        \ . 'rg --color=always -n -C3 -e "$p" -- "$f" 2>/dev/null | head -400 '
        \ . '|| sed -n 1,300p -- "$f"; '
        \ . 'else sed -n 1,300p -- "$f"; fi'

  let l:fzf = 'fzf --exact --ansi --layout=reverse --info=inline --cycle'
        \ . ' --delimiter=''\t'' --with-nth=''2..'''
        \ . ' --prompt=''検索 › '' --pointer=''▶'' --marker=''✓'''
        \ . ' --query=' . shellescape(a:initial)
        \ . ' --header=' . shellescape('⏎ 開く   ⎋ 移動   / 検索   1-9 行へ   ^/ プレビュー')
        \ . ' --preview-window=right:58%:wrap:border-left'
        \ . ' --preview ' . shellescape(l:preview)
        \ . ' --bind ' . shellescape('ctrl-/:toggle-preview,ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up')
        \ . ' --bind ' . shellescape(l:movebinds)
        \ . ' --bind ' . shellescape(l:modal)
        \ . ' --bind ' . shellescape('change:transform-query(printf %s {q} | sed "s/　/ /g")')
        \ . ' --bind ' . shellescape('load:transform-query(printf %s {q} | sed "s/　/ /g")')
  let l:cmd = l:src . ' | ' . l:fzf . ' > ' . shellescape(l:tmp)

  if get(g:, 'yurii_search_popup', 1) && has('popupwin') && has('terminal')
    " 中央フローティングポップアップで fzf を表示（分割ウィンドウにしない）
    " ポップアップでキー入力が効かない環境では let g:yurii_search_popup = 0
    let l:w = float2nr(&columns * 0.86)
    let l:h = float2nr(&lines * 0.78)
    let l:buf = term_start(['/bin/bash', '-c', l:cmd], {
          \ 'hidden': 1,
          \ 'term_finish': 'close',
          \ 'exit_cb': function('s:fzf_done', [l:tmp]),
          \ })
    let l:winid = popup_create(l:buf, {
          \ 'minwidth': l:w, 'maxwidth': l:w,
          \ 'minheight': l:h, 'maxheight': l:h,
          \ 'border': [1, 1, 1, 1], 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
          \ 'borderhighlight': ['Comment'], 'highlight': 'Normal',
          \ 'padding': [0, 1, 0, 1], 'zindex': 300,
          \ })
    call term_setsize(l:buf, l:h - 2, l:w - 4)
    " fzf 終了でバッファが消えたらポップアップも閉じる
    execute 'autocmd BufWipeout <buffer=' . l:buf . '> ++once call popup_close(' . l:winid . ')'
  else
    call term_start(['/bin/bash', '-c', l:cmd], {
          \ 'term_finish': 'close',
          \ 'exit_cb': function('s:fzf_done', [l:tmp]),
          \ })
  endif
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
