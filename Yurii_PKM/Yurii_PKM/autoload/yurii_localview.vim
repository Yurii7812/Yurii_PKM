function! yurii_localview#open(mode) abort
  if !yurii_localview#ensure_current_file()
    return
  endif
  call yurii_localview#write_state(a:mode)
  if !yurii_localview#is_running()
    call yurii_localview#start_viewer()
  else
    echom '[yurii_localview] synced (' . a:mode . ')'
  endif
endfunction

function! yurii_localview#mode(mode) abort
  if !yurii_localview#ensure_current_file()
    return
  endif
  call yurii_localview#write_state(a:mode)
  if !yurii_localview#is_running()
    call yurii_localview#start_viewer()
  else
    echom '[yurii_localview] mode = ' . a:mode
  endif
endfunction

function! yurii_localview#sync() abort
  if !yurii_localview#ensure_current_file()
    return
  endif
  call yurii_localview#write_state(yurii_localview#current_mode())
  if yurii_localview#is_running()
    echom '[yurii_localview] synced'
  else
    echom '[yurii_localview] viewer is not running. Use :YuriiLocalViewOpen'
  endif
endfunction

function! yurii_localview#maybe_sync() abort
  if yurii_localview#is_running() && yurii_localview#ensure_current_file(0)
    call yurii_localview#write_state(yurii_localview#current_mode())
  endif
endfunction

function! yurii_localview#status() abort
  let l:state = yurii_localview#read_state()
  let l:running = yurii_localview#is_running() ? 'running' : 'stopped'
  echom '[yurii_localview] ' . l:running
  if type(l:state) == type({}) && !empty(l:state)
    echom '  mode: ' . get(l:state, 'mode', '(none)')
    echom '  current: ' . get(l:state, 'current_file', '(none)')
    echom '  root: ' . get(l:state, 'root', '(none)')
  endif
endfunction

function! yurii_localview#stop() abort
  if !filereadable(g:yurii_localview_pid_path)
    echom '[yurii_localview] viewer is not running.'
    return
  endif
  let l:pid = trim(join(readfile(g:yurii_localview_pid_path), ''))
  if empty(l:pid)
    call delete(g:yurii_localview_pid_path)
    echom '[yurii_localview] stale pid file removed.'
    return
  endif
  call system('kill ' . shellescape(l:pid) . ' >/dev/null 2>&1')
  call delete(g:yurii_localview_pid_path)
  echom '[yurii_localview] stop requested.'
endfunction

function! yurii_localview#ensure_current_file(...) abort
  let l:quiet = a:0 ? a:1 : 1
  if &buftype !=# ''
    if l:quiet
      echohl ErrorMsg | echom '[yurii_localview] Current buffer is not a normal file.' | echohl None
    endif
    return 0
  endif
  let l:path = expand('%:p')
  if empty(l:path) || !filereadable(l:path)
    if l:quiet
      echohl ErrorMsg | echom '[yurii_localview] Current buffer has no readable file path.' | echohl None
    endif
    return 0
  endif
  return 1
endfunction

function! yurii_localview#state_dict(mode) abort
  let l:current = fnamemodify(expand('%:p'), ':p')
  let l:root = get(g:, 'yurii_localview_notes_root', '')
  if empty(l:root)
    let l:cwd = fnamemodify(getcwd(), ':p')
    if stridx(l:current, l:cwd) == 0
      let l:root = l:cwd
    else
      let l:root = fnamemodify(l:current, ':h')
    endif
  else
    let l:root = fnamemodify(expand(l:root), ':p')
  endif

  return {
        \ 'mode': a:mode,
        \ 'current_file': l:current,
        \ 'root': l:root,
        \ 'extensions': get(g:, 'yurii_localview_extensions', ['.md', '.markdown', '.txt']),
        \ 'use_first_heading_as_title': get(g:, 'yurii_localview_use_first_heading_as_title', 1),
        \ 'local_depth': get(g:, 'yurii_localview_local_depth', 2),
        \ 'label_limit': get(g:, 'yurii_localview_label_limit', 40),
        \ 'timestamp': reltimefloat(reltime()),
        \ }
endfunction

function! yurii_localview#write_state(mode) abort
  let l:state = yurii_localview#state_dict(a:mode)
  call writefile([json_encode(l:state)], g:yurii_localview_state_path)
endfunction

function! yurii_localview#read_state() abort
  if !filereadable(g:yurii_localview_state_path)
    return {}
  endif
  try
    return json_decode(join(readfile(g:yurii_localview_state_path), "\n"))
  catch
    return {}
  endtry
endfunction

function! yurii_localview#current_mode() abort
  let l:state = yurii_localview#read_state()
  let l:mode = get(l:state, 'mode', '')
  if l:mode ==# 'global' || l:mode ==# 'local'
    return l:mode
  endif
  return 'local'
endfunction

function! yurii_localview#is_running() abort
  if !filereadable(g:yurii_localview_pid_path)
    return 0
  endif
  let l:pid = trim(join(readfile(g:yurii_localview_pid_path), ''))
  if empty(l:pid)
    call delete(g:yurii_localview_pid_path)
    return 0
  endif
  let l:cmd = 'kill -0 ' . shellescape(l:pid) . ' >/dev/null 2>&1; printf %s $?'
  let l:status = trim(system('sh -c ' . shellescape(l:cmd)))
  if l:status ==# '0'
    return 1
  endif
  call delete(g:yurii_localview_pid_path)
  return 0
endfunction

function! yurii_localview#start_viewer() abort
  let l:script = g:yurii_localview_plugin_root . '/python/yurii_localview.py'
  if !filereadable(l:script)
    echohl ErrorMsg | echom '[yurii_localview] Python viewer script not found: ' . l:script | echohl None
    return
  endif

  let l:cmd = shellescape(get(g:, 'yurii_localview_python_cmd', 'python3'))
        \ . ' ' . shellescape(l:script)
        \ . ' --state ' . shellescape(g:yurii_localview_state_path)
        \ . ' --pidfile ' . shellescape(g:yurii_localview_pid_path)
        \ . ' --log ' . shellescape(g:yurii_localview_log_path)
        \ . ' >/dev/null 2>&1 &'

  call system('sh -c ' . shellescape(l:cmd))
  echom '[yurii_localview] viewer started.'
endfunction
