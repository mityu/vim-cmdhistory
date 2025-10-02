function cmdhistory#action#new() abort
  return deepcopy(s:action)
endfunction

function s:add(name, Fn) abort dict
  let self._actions[a:name] = a:Fn
endfunction

function s:remove(name) abort dict
  if !has_key(self._actions, a:name)
    call cmdhistory#util#show_error($'No action named "{a:name}" is registered.')
  endif
  call remove(self._actions, a:name)
endfunction

function s:invoke(name) abort dict
  if !has_key(self._actions, a:name)
    call cmdhistory#util#show_error($'No such action: {a:name}')
    return
  endif
  call call(self._actions[a:name], [])
endfunction

let s:action = #{
  \ _actions: {},
  \ add: function('s:add'),
  \ remove: function('s:remove'),
  \ invoke: function('s:invoke'),
  \ }
