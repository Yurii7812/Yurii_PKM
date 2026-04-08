" =============================================================================
" plugin/yurii_PKM.vim
" Unified entrypoint for yurii_PKM plugin bundle
" =============================================================================

if exists('g:loaded_yurii_pkm_bundle')
  finish
endif
let g:loaded_yurii_pkm_bundle = 1

" -----------------------------------------------------------------------------
" Load core PKM plugin (existing implementation)
" -----------------------------------------------------------------------------
let s:repo_root = fnamemodify(expand('<sfile>:p'), ':h:h')
let s:core_plugin = s:repo_root . '/yurii_PKM/plugin/yurii_PKM.vim'
if filereadable(s:core_plugin)
  execute 'source ' . fnameescape(s:core_plugin)
endif

" -----------------------------------------------------------------------------
" Load search plugin (existing implementation)
" -----------------------------------------------------------------------------
let s:search_plugin = s:repo_root . '/yurii_search/plugin/yurii_search.vim'
if filereadable(s:search_plugin)
  execute 'source ' . fnameescape(s:search_plugin)
endif

" -----------------------------------------------------------------------------
" Unified utility commands (previous standalone scripts)
" -----------------------------------------------------------------------------
command! -nargs=+ FileContentSearch call yurii_pkm_extra#file_content_search(<q-args>)
command! Rename call yurii_pkm_extra#rename_current_file()
command! SetImageSize call yurii_pkm_extra#set_image_size()
command! Autocwindow call yurii_pkm_extra#toggle_quickfix_advanced_mode()

augroup yurii_pkm_extra_quickfix
  autocmd!
  autocmd FileType qf call yurii_pkm_extra#quickfix_on_filetype()
augroup END
