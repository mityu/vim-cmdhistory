function cmdhistory#ff#new() abort
  return deepcopy(s:ff)
endfunction

function s:setup() abort dict
  call self._action.add('accept', { -> self._accept() })
  call self._action.add('quit', { -> self._terminate() })
  call self._action.add('redraw', { -> self._window.draw() })
  call self._action.add('select-next-item', { -> self._select_next_item() })
  call self._action.add('select-prev-item', { -> self._select_prev_item() })
  call self._action.add('go-forward', { -> self._prompt_go_forward() })
  call self._action.add('go-backward', { -> self._prompt_go_backward() })
  call self._action.add('go-head', { -> self._prompt_go_head() })
  call self._action.add('go-tail', { -> self._prompt_go_tail() })
  call self._action.add('delete-character', { -> self._prompt_delete_char() })
  call self._action.add('delete-word', { -> self._prompt_delete_word() })
  call self._action.add('delete-to-head', { -> self._prompt_delete_to_head() })
  call self._action.add('no-operation', { -> self._action_nop() })

  call self._source.capture()
  call self._window.open(
    \ { rawkey -> self._on_key_typed(rawkey) },
    \ { -> self._terminate() })
  let self._items = self._source.get()
  call self._window.set_items(self._items->copy())
  call self._window.set_prompt(self._prompt)
  call self._window.draw()
endfunction

function s:get_prompt() abort dict
  return cmdhistory#prompt#new_copy(self._prompt)
endfunction

function s:set_prompt(p) abort dict
  const text = self._prompt.text
  call self._prompt.copy_from(a:p)
  call self._window.set_prompt(a:p)
  call self._window.draw()
  if text !=# a:p.text
    call self._invoke_filter()
  endif
endfunction

function s:do_action(action) abort dict
  call self._action.invoke(a:action)
endfunction

function s:map_action(key, action) abort dict
  call self._keybind.add(a:key, a:action)
endfunction

function s:unmap_action(key) abort dict
  call self._keybind.remove(a:key)
endfunction

function s:add_action(action, Fn) abort dict
  call self._action.add(a:action, a:Fn)
endfunction

function s:remove_action(action) abort dict
  call self._action.remove(a:action)
endfunction

function s:on_key_typed(rawkey) abort dict
  const key = cmdhistory#util#normalize_keys(a:rawkey)
  const actions = self._keybind.get_keybind(key)

  if actions isnot v:null
    for action in actions
      call self._action.invoke(action)
    endfor
  else
    " Ignore special characters
    " See also: vim/src/keymap.h
    " TODO: Check K_NUL for MSDOS.
    if strpart(key, 0, 1) ==# "\x80"
      return
    endif

    const text = self._prompt.split_at_column()
    let self._prompt.text = text[0] .. key .. text[1]
    let self._prompt.column = self._prompt.column + strchars(key)
    call self._window.set_prompt(self._prompt)
    call self._invoke_filter()
  endif
endfunction

function s:invoke_filter() abort dict
  call self._filter.update_filter(self._prompt.text)

  const is_valid_filter = self._filter.get_filter_patterns_ref()
    \ ->mapnew({ _, v -> cmdhistory#util#is_valid_regex(v) })
    \ ->reduce({ acc, val -> acc && val }, v:true)

  if self._filter.get_filter_patterns_ref()->empty()
    let self._items = self._source.get()
    call self._window.set_items(self._items->copy())
    call self._window.update_highlight([])
  elseif is_valid_filter
    let self._items = self._filter.do(self._source.get())
    call self._window.set_items(self._items->copy())
    call self._window.update_highlight(self._filter.get_filter_patterns_ref())
  endif
  " do nothing when not all filter pattern is valid.

  " change selected item index to 0
  if self._selected_idx != 0
    const delta = -self._selected_idx
    let self._selected_idx = 0
    call self._window.move_selected_index(delta)
  endif
  call self._window.draw()
endfunction

function s:terminate() abort dict
  call self._window.close()
  call self._source.release()
  call self._filter.clear()
  call self._prompt.clear()
  let self._items = []
  let self._selected_idx = 0
endfunction

function s:select_next_item() abort dict
  const is_reversed = self._window.is_order_reversed()
  const delta = is_reversed ? -1 : 1
  const item_size = self._items->len()

  let self._selected_idx = self._selected_idx + delta
  if is_reversed && self._selected_idx < 0
    let self._selected_idx = item_size - 1
  elseif !is_reversed && self._selected_idx >= item_size
    let self._selected_idx = 0
  endif

  call self._window.move_selected_index(delta)
  call self._window.draw()
endfunction

function s:select_prev_item() abort dict
  const is_reversed = self._window.is_order_reversed()
  const delta = is_reversed ? 1 : -1
  const item_size = self._items->len()

  let self._selected_idx = self._selected_idx + delta
  if is_reversed && self._selected_idx >= item_size
    let self._selected_idx = 0
  elseif !is_reversed && self._selected_idx < 0
    let self._selected_idx = item_size - 1
  endif

  call self._window.move_selected_index(delta)
  call self._window.draw()
endfunction

function s:accept_item() abort dict
  if empty(self._items)
    return
  endif

  const selected = self._items[self._selected_idx]
  call self._terminate()
  if cmdhistory#util#in_cmdwin()
    if getline('$') ==# ''
      call setline('$', selected)
    else
      call append('$', selected)
    endif
    noautocmd normal! G$
  else
    call setcmdline(selected)
    redraw
  endif
endfunction

function s:prompt_go_forward() abort dict
  let p = self.get_prompt()
  const column = min([strchars(p.text), p.column + 1])
  if column != p.column
    let p.column = column
    call self.set_prompt(p)
  endif
endfunction

function s:prompt_go_backward() abort dict
  let p = self.get_prompt()
  const column = max([0, p.column - 1])
  if column != p.column
    let p.column = column
    call self.set_prompt(p)
  endif
endfunction

function s:prompt_go_head() abort dict
  let p = self.get_prompt()
  if p.column != 0
    let p.column = 0
    call self.set_prompt(p)
  endif
endfunction

function s:prompt_go_tail() abort dict
  let p = self.get_prompt()
  const column = strchars(p.text)
  if p.column != column
    let p.column = 0
    call self.set_prompt(p)
  endif
endfunction

function s:prompt_delete_char() abort dict
  let p = self.get_prompt()
  let text = p.split_at_column()
  if text[0] ==# ''
    return
  endif
  let text[0] = text[0]->strcharpart(0, strchars(text[0]) - 1)
  let p.column  = p.column - 1
  let p.text = text[0] .. text[1]
  call self.set_prompt(p)
endfunction

function s:prompt_delete_word() abort dict
  let p = self.get_prompt()
  if p.column != 0
    let text = p.split_at_column()
    let text[0] = text[0]->substitute('\<\w\+\s*$', '', '')
    let p.text = text[0] .. text[1]
    let p.column = strchars(text[0])
    call self.set_prompt(p)
  endif
endfunction

function s:prompt_delete_to_head() abort dict
  let p = self.get_prompt()
  if p.column != 0
    let p.text = p.split_at_column()[1]
    let p.column = 0
    call self.set_prompt(p)
  endif
endfunction

function s:action_nop() abort dict
  " no operation
endfunction

let s:ff = #{
  \ _action: cmdhistory#action#new(),
  \ _filter: cmdhistory#filter#new(),
  \ _keybind: cmdhistory#keybind#new(),
  \ _prompt: cmdhistory#prompt#new(),
  \ _source: cmdhistory#source#new(),
  \ _window: cmdhistory#window#new(),
  \ _items: [],
  \ _selected_idx: 0,
  \ setup: function('s:setup'),
  \ get_prompt: function('s:get_prompt'),
  \ set_prompt: function('s:set_prompt'),
  \ do_action: function('s:do_action'),
  \ map_action: function('s:map_action'),
  \ unmap_action: function('s:unmap_action'),
  \ add_action: function('s:add_action'),
  \ remove_action: function('s:remove_action'),
  \ _on_key_typed: function('s:on_key_typed'),
  \ _invoke_filter: function('s:invoke_filter'),
  \ _accept: function('s:accept_item'),
  \ _terminate: function('s:terminate'),
  \ _select_next_item: function('s:select_next_item'),
  \ _select_prev_item: function('s:select_prev_item'),
  \ _prompt_go_forward: function('s:prompt_go_forward'),
  \ _prompt_go_backward: function('s:prompt_go_backward'),
  \ _prompt_go_head: function('s:prompt_go_head'),
  \ _prompt_go_tail: function('s:prompt_go_tail'),
  \ _prompt_delete_char: function('s:prompt_delete_char'),
  \ _prompt_delete_word: function('s:prompt_delete_word'),
  \ _prompt_delete_to_head: function('s:prompt_delete_to_head'),
  \ _action_nop: function('s:action_nop'),
  \ }
