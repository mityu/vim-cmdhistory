let s:ff = cmdhistory#ff#new()

function cmdhistory#select() abort
  if getcmdtype() ==# '' && getcmdwintype() ==# ''
    call cmdhistory#util#show_error('Not in command-line or cmdwin')
    return
  endif
  call s:ff.setup()
endfunction

function cmdhistory#map_action(key, actions) abort
  call s:ff.map_action(a:key, a:actions)
endfunction

function cmdhistory#unmap_action(key) abort
  call s:ff.unmap_action(a:key)
endfunction

function cmdhistory#set_default_mappings() abort
  call s:ff.map_action('<CR>', ['accept'])
  call s:ff.map_action('<C-f>', ['go-forward'])
  call s:ff.map_action('<C-b>', ['go-backward'])
  call s:ff.map_action('<C-a>', ['go-head'])
  call s:ff.map_action('<C-e>', ['go-tail'])
  call s:ff.map_action('<C-h>', ['delete-character'])
  call s:ff.map_action('<BS>', ['delete-character'])
  call s:ff.map_action('<Del>', ['delete-character'])
  call s:ff.map_action('<C-w>', ['delete-word'])
  call s:ff.map_action('<C-u>', ['delete-to-head'])
  call s:ff.map_action('<C-p>', ['select-prev-item'])
  call s:ff.map_action('<C-k>', ['select-prev-item'])
  call s:ff.map_action('<C-n>', ['select-next-item'])
  call s:ff.map_action('<C-j>', ['select-next-item'])
  call s:ff.map_action('<C-l>', ['redraw'])
endfunction

function cmdhistory#Select()
  call cmdhistory#util#show_error('"cmdhistory#Select" function is deprecated.  Please use "cmdhistory#select" instead.')
  call cmdhistory#select()
endfunction

function cmdhistory#MapAction(key, actions)
  call cmdhistory#util#show_error('"cmdhistory#MapAction" function is deprecated.  Please use "cmdhistory#map_action" instead.')
  call cmdhistory#map_action(a:key, a:actions)
endfunction

function cmdhistory#UnmapAction(key)
  call cmdhistory#util#show_error('"cmdhistory#UnmapAction" function is deprecated.  Please use "cmdhistory#unmap_action" instead.')
  call cmdhistory#unmap_action(a:key)
endfunction

function cmdhistory#SetDefaultMappings()
  call cmdhistory#util#show_error('"cmdhistory#SetDefaultMappings" function is deprecated.  Please use "cmdhistory#set_default_mappings" instead.')
  call cmdhistory#set_default_mappings()
endfunction


" Emit autocommand for user configuration initializations.
augroup plugin-cmdhistory-dummy
  autocmd!
  autocmd User cmdhistory-initialize :
augroup END

doautocmd User cmdhistory-initialize

augroup plugin-cmdhistory-dummy
  autocmd!
augroup END
augroup! plugin-cmdhistory-dummy
