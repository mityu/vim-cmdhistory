function cmdhistory#prompt#new() abort
  return deepcopy(s:prompt)
endfunction

function cmdhistory#prompt#new_copy(rhs) abort
  let p = cmdhistory#prompt#new()
  call p.copy_from(a:rhs)
  return p
endfunction

function s:split_at_column() abort dict
  const len = strcharlen(self.text)
  return [
    \ strcharpart(self.text, 0, self.column, 1),
    \ strcharpart(self.text, self.column, len - self.column, 1)
    \ ]
endfunction

function s:copy_from(rhs) abort dict
  let self.column = a:rhs.column
  let self.text = a:rhs.text
endfunction

function s:clear() abort dict
  let self.column = 0
  let self.text = ''
endfunction

" The column is the 0-indexed character index.  Not byte index.
let s:prompt = #{
  \ column: 0,
  \ text: '',
  \ split_at_column: function('s:split_at_column'),
  \ copy_from: function('s:copy_from'),
  \ clear: function('s:clear'),
  \ }
