" =============================================================================
" autoload/yurii_pkm_extra.vim
" Extra helpers unified into yurii_PKM plugin bundle
" =============================================================================

if !exists('g:quickfix_advanced_mode')
  let g:quickfix_advanced_mode = 1
endif

function! yurii_pkm_extra#file_content_search(query) abort
  let tokens = split(tolower(a:query))
  let files = systemlist(['rg', '--files'])
  let items = []

  for f in files
    if !filereadable(f)
      continue
    endif

    let lines = readfile(f)
    let text  = tolower(join(lines, "\n"))

    let ok = 1
    for t in tokens
      if stridx(text, t) < 0
        let ok = 0
        break
      endif
    endfor

    if ok
      let best_lnum = 1
      let preview = ''

      for i in range(len(lines))
        let l = tolower(lines[i])
        for t in tokens
          if stridx(l, t) >= 0
            let best_lnum = i + 1
            let preview = lines[i]
            break
          endif
        endfor
        if preview !=# ''
          break
        endif
      endfor

      call add(items, {
            \ 'filename': f,
            \ 'lnum': best_lnum,
            \ 'col': 1,
            \ 'text': '[file-hit] ' . preview
            \ })
    endif
  endfor

  call setqflist(items, 'r', {'title': 'FileContentSearch: ' . a:query})
  copen
endfunction

function! yurii_pkm_extra#rename_current_file() abort
  let old_name = expand('%')
  let new_name = input('New file name: ', expand('%'), 'file')
  if new_name !=# '' && new_name !=# old_name
    execute 'saveas ' . fnameescape(new_name)
    call delete(old_name)
    redraw!
  endif
endfunction

function! yurii_pkm_extra#set_image_size() abort
  let line = getline('.')
  let col = col('.')

  let img_pattern = '<img src="\([^"]\+\)"[^>]*>'
  let img_match = matchstrpos(line, img_pattern)

  if img_match[1] != -1 && col >= img_match[1] + 1 && col <= img_match[2]
    let src = substitute(img_match[0], img_pattern, '\1', '')
    let size = input('Size: ')
    if size ==# ''
      return
    endif
    let img_tag = '<img src="' . src . '" width="' . size . '">'
    let new_line = strpart(line, 0, img_match[1]) . img_tag . strpart(line, img_match[2])
    call setline('.', new_line)
    return
  endif

  let md_pattern = '!\[\([^\]]*\)\](\([^)]\+\))'
  let md_match = matchstrpos(line, md_pattern)

  let src = ''
  let start_pos = -1
  let end_pos = -1

  if md_match[1] != -1
    let match_start = md_match[1]
    let match_end = md_match[2]
    if col >= match_start + 1 && col <= match_end
      let src = substitute(md_match[0], md_pattern, '\2', '')
      let start_pos = match_start
      let end_pos = match_end
    endif
  endif

  if src ==# ''
    let file_pattern = '\v[a-zA-Z0-9_\-./]+\.(jpg|jpeg|png|gif|webp|svg)'
    let pos = 0
    while 1
      let file_match = matchstrpos(line, file_pattern, pos)
      if file_match[1] == -1
        break
      endif
      if col >= file_match[1] + 1 && col <= file_match[2]
        let src = file_match[0]
        let start_pos = file_match[1]
        let end_pos = file_match[2]
        break
      endif
      let pos = file_match[2]
    endwhile
  endif

  if src ==# ''
    echo 'カーソル位置に画像が見つかりません'
    return
  endif

  let size = input('Size: ')
  if size ==# ''
    return
  endif

  let img_tag = '<img src="' . src . '" width="' . size . '">'
  let new_line = strpart(line, 0, start_pos) . img_tag . strpart(line, end_pos)
  call setline('.', new_line)
endfunction

function! s:set_quickfix_mappings() abort
  nnoremap <buffer> <silent> j j:cnext<CR><C-w>p
  nnoremap <buffer> <silent> k k:cprevious<CR><C-w>p
  nnoremap <buffer> <silent> <CR> <CR><C-w>p
endfunction

function! s:remove_quickfix_mappings() abort
  silent! nunmap <buffer> j
  silent! nunmap <buffer> k
  silent! nunmap <buffer> <CR>
endfunction

function! yurii_pkm_extra#toggle_quickfix_advanced_mode() abort
  if g:quickfix_advanced_mode
    let g:quickfix_advanced_mode = 0
    echo 'Quickfix Advanced Mode: OFF'
    if &filetype ==# 'qf'
      call s:remove_quickfix_mappings()
    endif
  else
    let g:quickfix_advanced_mode = 1
    echo 'Quickfix Advanced Mode: ON'
    if &filetype ==# 'qf'
      call s:set_quickfix_mappings()
    endif
  endif
endfunction

function! yurii_pkm_extra#quickfix_on_filetype() abort
  if g:quickfix_advanced_mode
    call s:set_quickfix_mappings()
  endif
endfunction
