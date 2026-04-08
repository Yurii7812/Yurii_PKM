" SetImageSize - マークダウン画像記法/ファイル名/imgタグをHTMLのimgタグに変換・編集
function! s:SetImageSize() abort
  let line = getline('.')
  let col = col('.')
  
  " パターン1: <img src="..." width="..."> 形式
  let img_pattern = '<img src="\([^"]\+\)"[^>]*>'
  let img_match = matchstrpos(line, img_pattern)
  
  if img_match[1] != -1 && col >= img_match[1] + 1 && col <= img_match[2]
    let src = substitute(img_match[0], img_pattern, '\1', '')
    let size = input('Size: ')
    if size == ''
      return
    endif
    let img_tag = '<img src="' . src . '" width="' . size . '">'
    let new_line = strpart(line, 0, img_match[1]) . img_tag . strpart(line, img_match[2])
    call setline('.', new_line)
    return
  endif
  
  " パターン2: ![alt](image.jpg) 形式
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
  
  " パターン3: 単純なファイル名 (image.jpg, image.png など)
  if src == ''
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
  
  if src == ''
    echo 'カーソル位置に画像が見つかりません'
    return
  endif
  
  let size = input('Size: ')
  if size == ''
    return
  endif
  
  let img_tag = '<img src="' . src . '" width="' . size . '">'
  let new_line = strpart(line, 0, start_pos) . img_tag . strpart(line, end_pos)
  call setline('.', new_line)
endfunction

command! SetImageSize call s:SetImageSize()