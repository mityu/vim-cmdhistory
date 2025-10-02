function cmdhistory#filter#new() abort
  return deepcopy(s:filter)
endfunction

function s:unescape_backslash(v) abort
  return substitute(a:v, '\v%(^|[^\\])%(\\\\)*\zs\\\ze\s', '', 'g')
endfunction

function s:filterer(filter_patterns, item) abort
  for p in a:filter_patterns
    if a:item !~# p
      return v:false
    endif
  endfor
  return v:true
endfunction

function s:get_filter_patterns_ref() abort dict
  return self._filter_patterns
endfunction

function s:clear() abort dict
  let self._filter_patterns = []
endfunction

function s:update_filter(input) abort dict
  let self._filter_patterns = a:input
    \ ->split('\v%(^|[^\\])%(\\\\)*\zs\s+')
    \ ->filter({ _, v -> v !=# '' })
    \ ->map({ _, v -> $'\c{s:unescape_backslash(v)}' })
endfunction

function s:do(items) abort dict
  return a:items->filter({ _, v -> s:filterer(self._filter_patterns, v) })
endfunction

let s:filter = #{
  \ _filter_patterns: [],
  \ get_filter_patterns_ref: function('s:get_filter_patterns_ref'),
  \ update_filter: function('s:update_filter'),
  \ clear: function('s:clear'),
  \ do: function('s:do'),
  \ }
