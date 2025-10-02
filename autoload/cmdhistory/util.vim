" Trans <KEY> into internal keycode representation.
function s:into_keycode(key) abort
  return eval(printf('"%s"', '\' .. a:key))
endfunction

function cmdhistory#util#normalize_keys(key) abort
  return substitute(a:key, '<.\{-}>', '\=s:into_keycode(submatch(0))', 'g')
endfunction

function cmdhistory#util#in_cmdwin() abort
  return getcmdwintype() !=# '' && getcmdtype() ==# ''
endfunction

function cmdhistory#util#is_valid_regex(r) abort
  try
    eval '' =~# a:r
  catch
    return v:false
  endtry
  return v:true
endfunction

function cmdhistory#util#show_error(msg) abort
  echohl Error
  echomsg '[cmdhistory]' a:msg
  echohl NONE
endfunction
