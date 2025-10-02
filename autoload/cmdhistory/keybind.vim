function cmdhistory#keybind#new() abort
  return deepcopy(s:keybind)
endfunction

function s:add(key, actions) abort dict
  let self._keybinds[cmdhistory#util#normalize_keys(a:key)] = copy(a:actions)
endfunction

function s:remove(key_given) abort dict
  const key = cmdhistory#util#normalize_keys(a:key_given)
  if !has_key(self._keybinds, key)
    call cmdhistory#util#show_error($'No keybind found for: {keytrans(a:key_given)}')
    return
  endif
  call remove(self._keybinds, key)
endfunction

function s:get_keybind(key) abort dict
  return get(self._keybinds, cmdhistory#util#normalize_keys(a:key), v:null)
endfunction

let s:keybind = #{
  \ _keybinds: {},
  \ add: function('s:add'),
  \ remove: function('s:remove'),
  \ get_keybind: function('s:get_keybind'),
  \ }
