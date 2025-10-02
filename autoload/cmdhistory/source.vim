function cmdhistory#source#new() abort
  return deepcopy(s:source)
endfunction

function s:capture() abort dict
  const histname = getcmdtype() ?? getcmdwintype()
  let self._items = range(1, histnr(histname))
    \ ->mapnew({ _, v -> histget(histname, v) })
    \ ->reverse()
endfunction

function s:release() abort dict
  let self._items = []
endfunction

function s:get() abort dict
  return copy(self._items)
endfunction

let s:source = #{
  \ _items: [],
  \ capture: function('s:capture'),
  \ release: function('s:release'),
  \ get: function('s:get'),
  \ }
