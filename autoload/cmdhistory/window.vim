const s:null_id = 0
const s:sign_name = 'cmdhistory-cursor'
const s:sign_group = 'PopUpCmdhistoryCursorline'

function cmdhistory#window#new() abort
  return deepcopy(s:window)
endfunction

function s:open(cb_on_close) abort dict
  call sign_define(s:sign_name, #{
    \ text: '>',
    \ linehl: 'Cursorline',
    \ })

  let self._cb_on_close = a:cb_on_close

  let self._height = &lines * 3 / 4
  if self._height < 25
    let self._height = min([25, &lines - 2])  " -2 is the margin for borders.
  endif

  let self._width = &columns * 3 / 4
  if self._width < 80
    let self._width = min([80, &columns - 2])  " -2 is the margin for borders.
  endif

  let self._display_range = [0, self._height - 1]  " -1 is the margin for prompt.

  let self._winid = self._open_window()

  if (getcmdtype() ?? getcmdwintype()) ==# ':'
    let syncmd = [
      \ 'syntax include @Vim syntax/vim.vim',
      \ $'syntax region CmdhistoryVimHighlightRegion start=/\%1l/ end=/\%{self._height}l/ contains=@Vim'
      \ ]
    call win_execute(self._winid, syncmd)
  endif
  call setwinvar(self._winid, '&signcolumn', 'yes')
endfunction

function s:bufnr() abort dict
  if self._winid == s:null_id
    return 0
  endif
  return winbufnr(self._winid)
endfunction

function s:set_prompt(new_prompt) abort dict
  call self._prompt.copy_from(a:new_prompt)
endfunction

function s:set_items(items) abort dict
  let self._items = a:items
endfunction

function s:update_highlight(patterns) abort dict
  if !self._matchids->empty()
    for id in self._matchids
      call matchdelete(id, self._winid)
    endfor
    let self._matchids = []
  endif
  for p in a:patterns
    let regex = $'\%({p}\m\)\%<{self._height}l'
    eval self._matchids->add(
      \ matchadd('Search', regex, 10, -1, #{ window: self._winid }))
  endfor
endfunction

function s:move_selected_index(delta) abort dict
  " NOTE: Items are rendered in reverse order on window, so 'go down'
  " comments in this function represents 'go cursor up' visually and also
  " 'go up' comments is 'go cursor down' in visual.
  const scrolloff = getwinvar(self._winid, '&scrolloff')
  const item_size = self._items->len()
  const height = self._height - 1  " Make sure the margin for prompt
  let firstidx = -1
  let need_scroll = v:true

  if item_size == 0
    let self._selected_idx = 0
    let self._display_range = [0, height]
    return
  endif

  let idx = self._selected_idx + a:delta
  while idx < 0
    let idx += item_size
  endwhile
  while idx >= item_size
    let idx -= item_size
  endwhile

  if height < (scrolloff * 2)
    " If scroll off overs half of window height, cursor will be always on
    " the center of window.
    let firstidx = idx - (height / 2) + 1
    if firstidx + height - 1 >= item_size
      let firstidx = item_size - height  " (item_size - 1) - (height - 1)
    endif
  elseif idx - scrolloff < self._display_range[0]
    if a:delta < 0
      " Went up.
      let firstidx = idx - scrolloff
    else
      " Went down and backed to the head.
      let firstidx = idx + scrolloff - (height - 1)
    endif
  elseif idx + scrolloff >= self._display_range[1]
    if a:delta >= 0
      " Went down.
      let firstidx = idx + scrolloff - (height - 1)
      if item_size - idx <= scrolloff
        let firstidx = item_size - height  " (item_size - 1) - (height - 1)
      endif
    else
      " Went up and backed to the tail.
      let firstidx = idx - scrolloff
      if firstidx + height - 1 >= item_size
        let firstidx = item_size - height  " (item_size - 1) - (height - 1)
      endif
    endif
  else
    let need_scroll = v:false
  endif

  if need_scroll
    if firstidx < 0
      let firstidx = 0
    endif
    let self._display_range = [firstidx, firstidx + height]
  endif

  let self._selected_idx = idx
endfunction

function s:draw() abort dict
  let bufnr = self.bufnr()

  " Draw items
  let contents = self._items
    \ ->slice(self._display_range[0], self._display_range[1])
    \ ->reverse()
  silent call deletebufline(bufnr, 1, '$')
  if contents->len() < self._height - 1
    call setbufline(bufnr, 1, ['']->repeat(self._height - contents->len() - 1))
    call appendbufline(bufnr, '$', contents)
  else
    call setbufline(bufnr, 1, contents)
  endif


  " Draw prompt
  const prompt = '>> '
  const margin = strchars(self._prompt.text) <= self._prompt.column ? ' ' : ''
  const width = self._width - prompt->strdisplaywidth() - 1 - 2

  let column = 0
  let text = ''
  if width > 0
    const input = self._prompt.split_at_column()
    let w = input[0]->strdisplaywidth()
    if w <= width
      let text = self._prompt.text
      let column = text->strlen() + prompt->strlen() + 1
    else
      " Need string truncation
      let i = 0
      for c in input[0]
        let i += 1
        let w -= c->strdisplaywidth()
        if w <= width
          let text = input[0][i :] .. input[1]
          let column = text->strlen() + prompt->strlen() + 1
          break
        endif
      endfor
    endif
  else
    let column = prompt->strlen()
  endif

  call appendbufline(bufnr, '$', $'{prompt}{text}{margin}')
  if self._cursor_match_id != s:null_id
    call matchdelete(self._cursor_match_id, self._winid)
    let self._cursor_match_id = s:null_id
  endif
  highlight def link CmdhistoryCursor Cursor
  let self._cursor_match_id = matchaddpos('CmdhistoryCursor',
    \ [[self._height, column]], 10, -1, #{ window: self._winid })


  " Draw cursorline
  if self._signid != s:null_id
    call sign_unplace(s:sign_group, #{ buffer: bufnr, id: self._signid })
    let self._signid = s:null_id
  endif
  const curline = self._height - 1 - (self._selected_idx - self._display_range[0])
  let self._signid = sign_place(0, s:sign_group, s:sign_name, bufnr, #{ lnum: curline })

  redraw
endfunction

" Returns TRUE if items are displayed in reversed order (i.e. newer items
" appears bottom).
function s:is_order_reversed() abort dict
  " This is always TRUE now.
  return v:true
endfunction

function s:on_closed() abort dict
  const CbOnClose = self._cb_on_close

  " Clear member variables
  let self._winid = s:null_id
  let self._signid = s:null_id
  let self._matchids = []
  let self._cursor_match_id = s:null_id
  call self._prompt.clear()
  let self._items = []
  let self._selected_idx = 0
  let self._display_range = []
  let self._width = 0
  let self._height = 0
  let self._cb_feedkey = v:null
  let self._cb_on_close = v:null

  call call(CbOnClose, [])
endfunction

if has('nvim')
  function s:open_window() abort dict
    const buf = nvim_create_buf(v:false, v:true)
    call nvim_set_option_value('bufhidden', 'wipe', #{ buf: buf })

    const row = (&lines - self._height) / 2
    const col = (&columns - self._width) / 2
    const winid = nvim_open_win(buf, v:false, #{
      \ relative: 'editor',
      \ row: row,
      \ col: col,
      \ width: self._width,
      \ height: self._height,
      \ border: "double",
      \ })
    call nvim_set_option_value('winhl', 'Normal:Normal', { 'win': winid })

    let g:cmdhistory_api = #{
      \ on_close: function('s:nvim_on_window_closed', [self]),
      \ }
    call nvim_create_autocmd('WinClosed', #{
      \ buffer: buf,
      \ once: v:true,
      \ nested: v:true,
      \ command: 'if exists("g:cmdhistory_api") | call call(g:cmdhistory_api.on_close, []) | endif',
      \ })
    return winid
  endfunction

  function s:close_window() abort dict
    if self._winid != s:null_id
      " Clear this._winid variable first to guard this infinite recursion.
      "    nvim_win_close() -> WinClosed -> s:close_window() -> nvim_win_close() -> ...
      let id = self._winid
      let self._winid = s:null_id
      call nvim_win_close(id, v:false)
    endif
  endfunction

  function s:nvim_on_window_closed(self) abort
    unlet! g:cmdhistory_api
    call a:self._on_closed()
  endfunction
else
  function s:open_window() abort dict
    return popup_create('', #{
      \ wrap: v:false,
      \ maxheight: self._height,
      \ minheight: self._height,
      \ maxwidth: self._width,
      \ minwidth: self._width,
      \ highlight: 'Normal',
      \ border: [1, 1, 1, 1],
      \ callback: { _winid, _idx -> self._on_closed() },
      \ })
  endfunction

  function s:close_window() abort dict
    if self._winid != s:null_id
      " Clear this._winid variable first to guard this infinite recursion.
      "    popup_close() -> popup-filter -> s:close_window() -> popup_close() -> ...
      let id = self._winid
      let self._winid = s:null_id
      call popup_close(id, -1)
    endif
  endfunction
endif

" _winid Window ID
" _signid Sign ID for the cursor line
" _matchids MatchIDs for highlighting matches
" _cursor_match_id MatchID for cursor on prompt
" _prompt User inputs
" _items Filtered history items
" _selected_idx Index of selected item
" _display_range Range in item index to be displayed; items in range [a, b) will be shown.
let s:window = #{
  \ _winid: s:null_id,
  \ _signid: s:null_id,
  \ _matchids: [],
  \ _cursor_match_id: s:null_id,
  \ _prompt: cmdhistory#prompt#new(),
  \ _items: [],
  \ _selected_idx: 0,
  \ _display_range: [],
  \ _width: 0,
  \ _height: 0,
  \ _cb_on_close: v:null,
  \ open: function('s:open'),
  \ bufnr: function('s:bufnr'),
  \ set_prompt: function('s:set_prompt'),
  \ set_items: function('s:set_items'),
  \ update_highlight: function('s:update_highlight'),
  \ move_selected_index: function('s:move_selected_index'),
  \ draw: function('s:draw'),
  \ close: function('s:close_window'),
  \ is_order_reversed: function('s:is_order_reversed'),
  \ _open_window: function('s:open_window'),
  \ _on_closed: function('s:on_closed'),
  \ }
