" autoload/yurii_search.vim
" ファイル単位のキーワード AND 検索。ネイティブのポップアップ。
"   打つ            … 絞り込み（タイトル+本文、全角スペースも区切り）
"   1-9 / 0         … その番号の行を開く（0 = 10 行目）
"   <C-j>/<C-k> ↓↑  … カーソル移動
"   <C-f>/<C-b>     … 1 画面送り / 戻し
"   <CR>           … カーソル行を開く
"   <Esc>/<C-c>    … 閉じる
"   <BS>           … 1 文字消す

let s:cands = []      " [{p,t,b}]
let s:query = ''
let s:hits  = []      " s:cands の index
let s:sel   = 0       " s:hits 内の位置
let s:top   = 0       " 表示の先頭（s:hits 内）
let s:win   = -1
let s:pvwin = -1
let s:rows  = 15

function! yurii_search#run(...) abort
  let l:idx = get(g:, 'yurii_search_index', '')
  if empty(l:idx) || !filereadable(l:idx)
    " python ヘルパーが無ければ旧 TUI
    call s:tui_run()
    return
  endif
  let l:root = get(g:, 'yurii_pkm_root', '')
  if empty(l:root) || !isdirectory(l:root)
    let l:root = getcwd()
  endif
  let l:raw = systemlist('python3 ' . shellescape(l:idx) . ' ' . shellescape(l:root))
  let s:cands = []
  for l:ln in l:raw
    let l:f = split(l:ln, "\t", 1)
    if len(l:f) >= 2
      call add(s:cands, {'p': l:f[0], 't': l:f[1], 'b': get(l:f, 2, '')})
    endif
  endfor
  if empty(s:cands)
    echo 'yurii_search: ノートが見つかりません（' . l:root . '）'
    return
  endif

  let s:query = a:0 > 0 ? a:1 : ''
  let s:sel = 0
  let s:top = 0
  call s:refilter()

  let l:w = min([float2nr(&columns * 0.42), 70])
  let s:rows = max([8, min([&lines - 8, 22])])
  let l:col = (&columns - (l:w + 2 + float2nr(&columns * 0.42))) / 2
  let l:line = (&lines - (s:rows + 4)) / 2

  let s:win = popup_create([], {
        \ 'line': l:line, 'col': max([l:col, 2]),
        \ 'minwidth': l:w, 'maxwidth': l:w,
        \ 'minheight': s:rows + 2, 'maxheight': s:rows + 2,
        \ 'border': [], 'borderchars': ['─','│','─','│','╭','╮','╯','╰'],
        \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1],
        \ 'title': ' 検索 ', 'zindex': 300,
        \ 'mapping': 0, 'filter': function('s:key'), 'callback': function('s:done'),
        \ })
  let s:pvwin = popup_create([], {
        \ 'line': l:line, 'col': max([l:col, 2]) + l:w + 3,
        \ 'minwidth': float2nr(&columns * 0.42), 'maxwidth': float2nr(&columns * 0.42),
        \ 'minheight': s:rows + 2, 'maxheight': s:rows + 2,
        \ 'border': [], 'borderchars': ['─','│','─','│','╭','╮','╯','╰'],
        \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1],
        \ 'title': ' プレビュー ', 'zindex': 299,
        \ })
  call s:render()
endfunction

" --- フィルタ ---------------------------------------------------------------
function! s:refilter() abort
  let l:q = substitute(s:query, '　', ' ', 'g')
  let l:terms = filter(split(l:q, ' '), 'v:val !=# ""')
  let s:hits = []
  let l:i = 0
  for l:c in s:cands
    let l:hay = l:c.t . ' ' . l:c.b
    let l:ok = 1
    for l:t in l:terms
      if stridx(l:hay, l:t) < 0
        let l:ok = 0 | break
      endif
    endfor
    if l:ok | call add(s:hits, l:i) | endif
    let l:i += 1
  endfor
  if s:sel >= len(s:hits) | let s:sel = max([0, len(s:hits) - 1]) | endif
  if s:sel < s:top | let s:top = s:sel | endif
  if s:sel >= s:top + s:rows | let s:top = s:sel - s:rows + 1 | endif
  if s:top < 0 | let s:top = 0 | endif
endfunction

" --- 描画 -----------------------------------------------------------------
function! s:render() abort
  if s:win < 0 | return | endif
  let l:lines = ['> ' . s:query . (empty(s:query) ? '▏' : '▏'), repeat('─', 60)]
  if empty(s:hits)
    call add(l:lines, '  (該当なし)')
  else
    let l:end = min([s:top + s:rows, len(s:hits)])
    let l:n = 1
    for l:vi in range(s:top, l:end - 1)
      let l:c = s:cands[s:hits[l:vi]]
      let l:num = (l:n <= 9) ? l:n : (l:n == 10 ? 0 : ' ')
      let l:mark = (l:vi == s:sel) ? '▶' : ' '
      call add(l:lines, printf('%s%s %s', l:mark, l:num, l:c.t))
      let l:n += 1
    endfor
  endif
  let l:foot = printf('%d/%d   1-9 開く  ^J^K 移動  ^F^B 送り  ⏎ 開く  ⎋ 閉じる',
        \ empty(s:hits) ? 0 : s:sel + 1, len(s:hits))
  call add(l:lines, repeat('─', 60))
  call add(l:lines, l:foot)
  call popup_settext(s:win, l:lines)
  call s:preview()
endfunction

function! s:preview() abort
  if s:pvwin < 0 | return | endif
  if empty(s:hits)
    call popup_settext(s:pvwin, ['(なし)'])
    return
  endif
  let l:c = s:cands[s:hits[s:sel]]
  let l:q = substitute(s:query, '　', ' ', 'g')
  let l:terms = filter(split(l:q, ' '), 'v:val !=# ""')
  let l:body = readfile(l:c.p, '', 400)
  if empty(l:terms)
    call popup_settext(s:pvwin, l:body[0:300])
    return
  endif
  " ヒット行 ± 前後 2 行
  let l:show = []
  let l:i = 0
  for l:ln in l:body
    for l:t in l:terms
      if stridx(l:ln, l:t) >= 0
        for l:j in range(max([0, l:i - 2]), min([len(l:body) - 1, l:i + 2]))
          if index(l:show, l:j) < 0 | call add(l:show, l:j) | endif
        endfor
        break
      endif
    endfor
    let l:i += 1
  endfor
  call sort(l:show, 'n')
  if empty(l:show)
    call popup_settext(s:pvwin, l:body[0:300])
    return
  endif
  let l:out = []
  let l:prev = -2
  for l:j in l:show
    if l:j > l:prev + 1 && !empty(l:out) | call add(l:out, '  ⋯') | endif
    call add(l:out, printf('%4d %s', l:j + 1, l:body[l:j]))
    let l:prev = l:j
  endfor
  call popup_settext(s:pvwin, l:out)
endfunction

" --- キー処理 -----------------------------------------------------------------
function! s:key(winid, key) abort
  if a:key ==# "\<Esc>" || a:key ==# "\<C-c>"
    call popup_close(a:winid, -1)
    return 1
  elseif a:key ==# "\<CR>"
    call popup_close(a:winid, empty(s:hits) ? -1 : s:hits[s:sel])
    return 1
  elseif a:key ==# "\<C-j>" || a:key ==# "\<Down>"
    let s:sel = min([s:sel + 1, max([0, len(s:hits) - 1])])
  elseif a:key ==# "\<C-k>" || a:key ==# "\<Up>"
    let s:sel = max([s:sel - 1, 0])
  elseif a:key ==# "\<C-f>" || a:key ==# "\<PageDown>"
    let s:sel = min([s:sel + s:rows, max([0, len(s:hits) - 1])])
  elseif a:key ==# "\<C-b>" || a:key ==# "\<PageUp>"
    let s:sel = max([s:sel - s:rows, 0])
  elseif a:key ==# "\<C-d>"
    let s:sel = min([s:sel + s:rows / 2, max([0, len(s:hits) - 1])])
  elseif a:key ==# "\<C-u>"
    let s:sel = max([s:sel - s:rows / 2, 0])
  elseif a:key ==# "\<BS>" || a:key ==# "\<C-h>"
    let s:query = strcharpart(s:query, 0, strchars(s:query) - 1)
    let s:sel = 0 | let s:top = 0
  elseif a:key ==# "\<C-w>" || a:key ==# "\<C-u>"
    let s:query = '' | let s:sel = 0 | let s:top = 0
  elseif a:key =~# '^[0-9]$'
    let l:row = (a:key ==# '0') ? 10 : str2nr(a:key)
    let l:target = s:top + l:row - 1
    if l:target >= 0 && l:target < len(s:hits)
      call popup_close(a:winid, s:hits[l:target])
      return 1
    endif
    " 表示外の番号は無視
  elseif strchars(a:key) == 1 && a:key !~# '[[:cntrl:]]'
    let s:query .= a:key
    let s:sel = 0 | let s:top = 0
  else
    return 1
  endif
  call s:refilter()
  call s:render()
  return 1
endfunction

function! s:done(winid, result) abort
  let s:win = -1
  if s:pvwin >= 0
    call popup_close(s:pvwin)
    let s:pvwin = -1
  endif
  if type(a:result) == v:t_number && a:result >= 0 && a:result < len(s:cands)
    execute 'edit ' . fnameescape(s:cands[a:result].p)
  endif
endfunction

" --- 旧 curses TUI（python ヘルパーが無い時のみ）----------------------------
function! s:tui_run() abort
  let l:script = get(g:, 'yurii_search_tui', '')
  if !filereadable(l:script)
    echoerr 'notes_index.py も fsearch_tui.py も見つかりません'
    return
  endif
  let l:tmpfile = tempname()
  let l:cmd = 'python3 ' . shellescape(l:script) . ' ' . shellescape(getcwd())
        \ . ' ' . shellescape(l:tmpfile)
  call term_start(['/bin/bash', '-c', l:cmd], {
        \ 'term_finish': 'close',
        \ 'exit_cb': function('s:tui_done', [l:tmpfile]),
        \ })
endfunction

function! s:tui_done(tmpfile, job, status) abort
  if !filereadable(a:tmpfile) | return | endif
  let l:sel = trim(join(readfile(a:tmpfile), ''))
  call delete(a:tmpfile)
  if l:sel != '' | execute 'edit ' . fnameescape(l:sel) | endif
endfunction
