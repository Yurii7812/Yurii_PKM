" plugin/yurii_search.vim

if exists('g:loaded_yurii_search')
  finish
endif
let g:loaded_yurii_search = 1

" fsearch_tui.py のパス（デフォルト: plugin/../python/fsearch_tui.py）
if !exists('g:yurii_search_tui')
  let g:yurii_search_tui = expand('<sfile>:p:h:h') . '/python/fsearch_tui.py'
endif
if !exists('g:yurii_search_python_cmd')
  let g:yurii_search_python_cmd = executable('python3') ? 'python3' : 'python'
endif

command! -nargs=0 FSearch call yurii_search#run()

if !exists('g:yurii_search_no_mappings')
  nnoremap <leader>fs :FSearch<CR>
endif
