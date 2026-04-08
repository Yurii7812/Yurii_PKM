if exists('g:loaded_yurii_localview')
  finish
endif
let g:loaded_yurii_localview = 1

if !exists('g:yurii_localview_python_cmd')
  let g:yurii_localview_python_cmd = executable('python3') ? 'python3' : 'python'
endif
if !executable(g:yurii_localview_python_cmd)
  echohl ErrorMsg
  echom '[yurii_localview] python3/python is required.'
  echohl None
  finish
endif

if !exists('g:yurii_localview_notes_root')
  let g:yurii_localview_notes_root = ''
endif

if !exists('g:yurii_localview_extensions')
  let g:yurii_localview_extensions = ['.md', '.markdown', '.txt']
endif

if !exists('g:yurii_localview_use_first_heading_as_title')
  let g:yurii_localview_use_first_heading_as_title = 1
endif

if !exists('g:yurii_localview_local_depth')
  let g:yurii_localview_local_depth = 2
endif

if !exists('g:yurii_localview_auto_sync')
  let g:yurii_localview_auto_sync = 1
endif

if !exists('g:yurii_localview_label_limit')
  let g:yurii_localview_label_limit = 40
endif

let s:plugin_root = fnamemodify(expand('<sfile>:p'), ':h:h')
let s:cache_dir = expand('~/.cache/yurii_localview')
if !isdirectory(s:cache_dir)
  call mkdir(s:cache_dir, 'p')
endif

if !exists('g:yurii_localview_plugin_root')
  let g:yurii_localview_plugin_root = s:plugin_root
endif
if !exists('g:yurii_localview_state_path')
  let g:yurii_localview_state_path = s:cache_dir . '/state.json'
endif
if !exists('g:yurii_localview_pid_path')
  let g:yurii_localview_pid_path = s:cache_dir . '/viewer.pid'
endif
if !exists('g:yurii_localview_log_path')
  let g:yurii_localview_log_path = s:cache_dir . '/viewer.log'
endif

command! YuriiLocalViewOpen call yurii_localview#open('local')
command! YuriiLocalViewGlobal call yurii_localview#open('global')
command! YuriiLocalViewLocal call yurii_localview#mode('local')
command! YuriiLocalViewLocalRefresh call yurii_localview#mode('local')
command! YuriiLocalViewGlobalRefresh call yurii_localview#mode('global')
command! YuriiLocalViewSync call yurii_localview#sync()
command! YuriiLocalViewStop call yurii_localview#stop()
command! YuriiLocalViewStatus call yurii_localview#status()

augroup yurii_localview_autosync
  autocmd!
  if get(g:, 'yurii_localview_auto_sync', 1)
    autocmd BufEnter,BufWritePost * call yurii_localview#maybe_sync()
  endif
augroup END
