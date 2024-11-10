vim9script

type ActionFunc = func(): void

def Error(msg: string)
  echohl Error
  echomsg '[cmdhistory]' msg
  echohl NONE
enddef

def NormalizeKeys(key: string): string
  const Sub = (m: list<string>): string => eval(printf('"%s"', '\' .. m[0]))
  return substitute(key, '<.\{-}>', Sub, 'g')
enddef

def IsValidRegex(r: string): bool
  try
    eval '' =~# r
  catch
    return false
  endtry
  return true
enddef

def InCmdwin(): bool
  return getcmdwintype() !=# '' && getcmdtype() ==# ''
enddef

class Prompt
  public var column = 0  # Column index in chars
  public var text = ''

  def newCopy(rhs: any)
    this.CopyFrom(rhs)
  enddef

  def SplitAtColumn(): list<string>
    return [strcharpart(this.text, 0, this.column, 1), this.text[this.column :]]
  enddef

  def CopyFrom(rhsGiven: any)
    const rhs: Prompt = rhsGiven
    this.column = rhs.column
    this.text = rhs.text
  enddef

  def Clear()
    this.column = 0
    this.text = ''
  enddef
endclass


class Source
  # Raw history entries.
  var _items: list<string>

  def Capture()
    const histname = getcmdtype() ?? getcmdwintype()
    this._items = range(1, histnr(histname))
      ->mapnew((_: number, v: number): string => histget(histname, v))
      ->reverse()
  enddef

  def Release()
    this._items = []
  enddef

  def Get(): list<string>
    return copy(this._items)
  enddef
endclass


class Window
  static const nullID = 0
  static const signName = 'cmdhistory-cursor'
  static const signGroup = 'PopUpCmdhistoryCursorline'

  var _winid: number = nullID
  var _signid: number = nullID  # SignID for cursor line
  var _matchids: list<number>  # MatchIDs for highlighting matches
  var _cursorMatchID: number = nullID  # MatchID for cursor on prompt

  var _prompt: Prompt = Prompt.new()  # User inputs
  var _items: list<string>  # Filtered history items
  var _selectedIdx: number  # Index of selected item

  # Range in item index to be displayed; items in range [a, b) will be shown.
  var _displayRange: list<number>

  var _width: number
  var _height: number

  var CbFeedkey: func(string)  # See :h E704.
  var CbOnClose: func()

  def Open(CbFeedkey: func(string), CbOnClose: func())
    sign_define(signName, {
      text: '>',
      linehl: 'Cursorline',
    })

    this.CbFeedkey = CbFeedkey
    this.CbOnClose = CbOnClose

    this._height = &lines * 3 / 4
    if this._height < 25
      this._height = min([25, &lines - 2])  # -2 is the margin for borders.
    endif

    this._width = &columns * 3 / 4
    if this._width < 80
      this._width = min([80, &columns - 2])  # -2 is the margin for borders.
    endif

    this._displayRange = [0, this._height - 1]  # -1 is the margin for prompt.

    this._winid = popup_create('', {
      wrap: false,
      maxheight: this._height,
      minheight: this._height,
      maxwidth: this._width,
      minwidth: this._width,
      highlight: 'Normal',
      border: [1, 1, 1, 1],
      filter: this._keyFilter,
      mapping: false,
      callback: this._onClosed,
    })
    if (getcmdtype() ?? getcmdwintype()) ==# ':'
      var syncmd = [
        'syntax include @Vim syntax/vim.vim',
        $'syntax region CmdhistoryVimHighlightRegion start=/\%1l/ end=/\%{this._height}l/ contains=@Vim'
      ]
      win_execute(this._winid, syncmd)
    endif
    setwinvar(this._winid, '&signcolumn', 'yes')
  enddef

  def Bufnr(): number
    if this._winid == nullID
      return 0
    endif
    return winbufnr(this._winid)
  enddef

  def SetPrompt(newPrompt: Prompt)
    this._prompt.CopyFrom(newPrompt)
  enddef

  def SetItems(items: list<string>)
    this._items = items
  enddef

  def UpdateHighlight(patterns: list<string>)
    if !this._matchids->empty()
      for id in this._matchids
        matchdelete(id, this._winid)
      endfor
      this._matchids = []
    endif
    for p in patterns
      var regex = $'\%({p}\m\)\%<{this._height}l'
      this._matchids->add(
        matchadd('Search', regex, 10, -1, {window: this._winid}))
    endfor
  enddef

  def MoveSelectedIndex(delta: number)
    # NOTE: Items are rendered in reverse order on window, so 'go down'
    # comments in this function represents 'go cursor up' visually and also
    # 'go up' comments is 'go cursor down' in visual.
    const scrolloff = getwinvar(this._winid, '&scrolloff')
    const itemSize = this._items->len()
    const height = this._height - 1  # Make sure the margin for prompt
    var firstidx = -1
    var needScroll = true

    if itemSize == 0
      this._selectedIdx = 0
      this._displayRange = [0, height]
      return
    endif

    var idx = this._selectedIdx + delta
    while idx < 0
      idx += itemSize
    endwhile
    while idx >= itemSize
      idx -= itemSize
    endwhile

    if height < (scrolloff * 2)
      # If scroll off overs half of window height, cursor will be always on
      # the center of window.
      firstidx = idx - (height / 2) + 1
      if firstidx + height - 1 >= itemSize
        firstidx = itemSize - height  # (itemSize - 1) - (height - 1)
      endif
    elseif idx - scrolloff < this._displayRange[0]
      if delta < 0
        # Went up.
        firstidx = idx - scrolloff
      else
        # Went down and backed to the head.
        firstidx = idx + scrolloff - (height - 1)
      endif
    elseif idx + scrolloff >= this._displayRange[1]
      if delta >= 0
        # Went down.
        firstidx = idx + scrolloff - (height - 1)
        if itemSize - idx <= scrolloff
          firstidx = itemSize - height  # (itemSize - 1) - (height - 1)
        endif
      else
        # Went up and backed to the tail.
        firstidx = idx - scrolloff
        if firstidx + height - 1 >= itemSize
          firstidx = itemSize - height  # (itemSize - 1) - (height - 1)
        endif
      endif
    else
      needScroll = false
    endif

    if needScroll
      if firstidx < 0
        firstidx = 0
      endif
      this._displayRange = [firstidx, firstidx + height]
    endif

    this._selectedIdx = idx
  enddef

  def Draw()
    var bufnr = this.Bufnr()

    # Draw items
    var contents = this._items
      ->slice(this._displayRange[0], this._displayRange[1])
      ->reverse()
    silent deletebufline(bufnr, 1, '$')
    if contents->len() < this._height - 1
      setbufline(bufnr, 1, ['']->repeat(this._height - contents->len() - 1))
      appendbufline(bufnr, '$', contents)
    else
      setbufline(bufnr, 1, contents)
    endif


    # Draw prompt
    const prompt = '>> '
    const margin = strchars(this._prompt.text) <= this._prompt.column ? ' ' : ''
    const width = this._width - prompt->strdisplaywidth() - 1 - 2

    var column = 0
    var text = ''
    if width > 0
      const input = this._prompt.SplitAtColumn()
      var w = input[0]->strdisplaywidth()
      if w <= width
        text = this._prompt.text
        column = text->strlen() + prompt->strlen() + 1
      else
        # Need string truncation
        var i = 0
        for c in input[0]
          ++i
          w -= c->strdisplaywidth()
          if w <= width
            text = input[0][i :] .. input[1]
            column = text->strlen() + prompt->strlen() + 1
            break
          endif
        endfor
      endif
    else
      column = prompt->strlen()
    endif

    appendbufline(bufnr, '$', $'{prompt}{text}{margin}')
    if this._cursorMatchID != nullID
      matchdelete(this._cursorMatchID, this._winid)
      this._cursorMatchID = nullID
    endif
    highlight def link CmdhistoryCursor Cursor
    this._cursorMatchID = matchaddpos('CmdhistoryCursor',
      [[this._height, column]], 10, -1, {window: this._winid})


    # Draw cursorline
    if this._signid != nullID
      sign_unplace(signGroup, {buffer: bufnr, id: this._signid})
      this._signid = nullID
    endif
    const curline = this._height - 1 - (this._selectedIdx - this._displayRange[0])
    this._signid = sign_place(0, signGroup, signName, bufnr, {lnum: curline})

    if !InCmdwin()
      redraw
    endif
  enddef

  def Close()
    if this._winid != nullID
      # Clear this._winid variable first to guard this infinite recursion.
      #    popup_close() -> popup-filter -> Close() -> popup_close() -> ...
      var id = this._winid
      this._winid = nullID
      popup_close(id, -1)
    endif
  enddef

  # Returns TRUE if items are displayed in reversed order (i.e. newer items
  # appears bottom).
  def IsOrderReversed(): bool
    # This is always TRUE now.
    return true
  enddef

  def _keyFilter(_: number, key: string): number
    call(this.CbFeedkey, [key])
    return 1
  enddef

  def _onClosed(id: number, selected: number)
    const CbOnClose = this.CbOnClose

    # Clear member variables
    this._winid = nullID
    this._signid = nullID
    this._matchids = []
    this._cursorMatchID = nullID
    this._prompt.Clear()
    this._items = []
    this._selectedIdx = 0
    this._displayRange = []
    this._width = 0
    this._height = 0
    this.CbFeedkey = null_function
    this.CbOnClose = null_function

    call(CbOnClose, [])
  enddef
endclass


class Filter
  var filterPatterns: list<string>

  def Clear()
    this.filterPatterns = []
  enddef

  def UpdateFilter(input: string)
    const UnescapeBsh = (v: string): string =>
      substitute(v, '\v%(^|[^\\])%(\\\\)*\zs\\\ze\s', '', 'g')
    this.filterPatterns = input
      ->split('\v%(^|[^\\])%(\\\\)*\zs\s+')
      ->filter((_, v: string): bool => v !=# '')
      ->map((_, v: string): string => $'\c{UnescapeBsh(v)}')
  enddef

  def Do(items: list<string>): list<string>
    return items->filter((_: number, v: string): bool => this._checkOne(v))
  enddef

  def _checkOne(item: string): bool
    for p in this.filterPatterns
      if item !~# p
        return false
      endif
    endfor
    return true
  enddef
endclass


class Action
  var _actions: dict<ActionFunc>

  def Add(name: string, Fn: ActionFunc)
    this._actions[name] = Fn
  enddef

  def Remove(name: string)
    if !has_key(this._actions, name)
      Error($'No action named "{name}" is registered.')
    endif
    remove(this._actions, name)
  enddef

  def Invoke(name: string)
    if !has_key(this._actions, name)
      Error($'No such action: {name}')
      return
    endif
    call(this._actions[name], [])
  enddef
endclass


class Keybind
  var _keybinds: dict<list<string>>

  def Add(key: string, actions: list<string>)
    this._keybinds[NormalizeKeys(key)] = copy(actions)
  enddef

  def Remove(keyGiven: string)
    const key = NormalizeKeys(keyGiven)
    if !has_key(this._keybinds, key)
      Error($'No keybind found for: {keytrans(keyGiven)}')
      return
    endif
    remove(this._keybinds, key)
  enddef

  def GetKeybind(key: string): list<string>
    return get(this._keybinds, NormalizeKeys(key), null_list)
  enddef
endclass


class FF
  var _action: Action
  var _filter: Filter
  var _keybind: Keybind
  var _prompt: Prompt
  var _source: Source
  var _window: Window

  var _items: list<string>
  var _selectedIdx: number

  def new()
    this._action = Action.new()
    this._filter = Filter.new()
    this._keybind = Keybind.new()
    this._prompt = Prompt.new()
    this._source = Source.new()
    this._window = Window.new()

    this._action.Add('accept', this._acceptItem)
    this._action.Add('quit', this._terminate)
    this._action.Add('redraw', this._window.Draw)
    this._action.Add('select-next-item', this._selectNextItem)
    this._action.Add('select-prev-item', this._selectPrevItem)
    this._action.Add('go-forward', this._promptGoForward)
    this._action.Add('go-backward', this._promptGoBackward)
    this._action.Add('go-head', this._promptGoHead)
    this._action.Add('go-tail', this._promptGoTail)
    this._action.Add('delete-character', this._promptDeleteChar)
    this._action.Add('delete-word', this._promptDeleteWord)
    this._action.Add('delete-to-head', this._promptDeleteToHead)
    this._action.Add('no-operation', this._actionNop)
  enddef

  def Setup()
    this._source.Capture()
    this._window.Open(this._onKeyTyped, this._terminate)
    this._items = this._source.Get()
    this._window.SetItems(this._items->copy())
    this._window.SetPrompt(this._prompt)
    this._window.Draw()
  enddef

  def GetPrompt(): Prompt
    return Prompt.newCopy(this._prompt)
  enddef

  def SetPrompt(p: Prompt)
    const text = this._prompt.text
    this._prompt.CopyFrom(p)
    this._window.SetPrompt(p)
    this._window.Draw()
    if text !=# p.text
      this._invokeFilter()
    endif
  enddef

  def DoAction(action: string)
    this._action.Invoke(action)
  enddef

  def MapAction(key: string, action: list<string>)
    this._keybind.Add(key, action)
  enddef

  def UnmapAction(key: string)
    this._keybind.Remove(key)
  enddef

  def AddAction(action: string, Fn: ActionFunc)
    this._action.Add(action, Fn)
  enddef

  def RemoveAction(action: string)
    this._action.Remove(action)
  enddef

  def _onKeyTyped(keyGiven: string)
    const key = NormalizeKeys(keyGiven)
    const actions = this._keybind.GetKeybind(key)

    if actions != null_list
      for action in actions
        this._action.Invoke(action)
      endfor
    else
      # Ignore special characters
      # See also: vim/src/keymap.h
      # TODO: Check K_NUL for MSDOS.
      if strpart(key, 0, 1) ==# "\x80"
        return
      endif

      const text = this._prompt.SplitAtColumn()
      this._prompt.text = text[0] .. key .. text[1]
      this._prompt.column = this._prompt.column + strchars(key)
      this._window.SetPrompt(this._prompt)
      this._invokeFilter()
    endif
  enddef

  def _invokeFilter()
    this._filter.UpdateFilter(this._prompt.text)

    const isValidFilter = this._filter.filterPatterns
      ->mapnew((_: number, v: string): bool => IsValidRegex(v))
      ->reduce((acc: bool, val: bool): bool => acc && val, true)

    if this._filter.filterPatterns->empty()
      this._items = this._source.Get()
      this._window.SetItems(this._items->copy())
      this._window.UpdateHighlight([])
    elseif isValidFilter
      this._items = this._filter.Do(this._source.Get())
      this._window.SetItems(this._items->copy())
      this._window.UpdateHighlight(this._filter.filterPatterns)
    endif
    # Do nothing when not all filter pattern is valid.

    # Change selected item index to 0
    if this._selectedIdx != 0
      const delta = -this._selectedIdx
      this._selectedIdx = 0
      this._window.MoveSelectedIndex(delta)
    endif
    this._window.Draw()
  enddef

  def _terminate()
    this._window.Close()
    this._source.Release()
    this._filter.Clear()
    this._prompt.Clear()
    this._items = []
    this._selectedIdx = 0
  enddef

  def _selectNextItem()
    const isReversed = this._window.IsOrderReversed()
    const delta = isReversed ? -1 : 1
    const itemSize = this._items->len()

    this._selectedIdx = this._selectedIdx + delta
    if isReversed && this._selectedIdx < 0
      this._selectedIdx = itemSize - 1
    elseif !isReversed && this._selectedIdx >= itemSize
      this._selectedIdx = 0
    endif

    this._window.MoveSelectedIndex(delta)
    this._window.Draw()
  enddef

  def _selectPrevItem()
    const isReversed = this._window.IsOrderReversed()
    const delta = isReversed ? 1 : -1
    const itemSize = this._items->len()

    this._selectedIdx = this._selectedIdx + delta
    if isReversed && this._selectedIdx >= itemSize
      this._selectedIdx = 0
    elseif !isReversed && this._selectedIdx < 0
      this._selectedIdx = itemSize - 1
    endif

    this._window.MoveSelectedIndex(delta)
    this._window.Draw()
  enddef

  def _acceptItem()
    if empty(this._items)
      return
    endif

    const selected = this._items[this._selectedIdx]
    this._terminate()
    if InCmdwin()
      if getline('$') ==# ''
        setline('$', selected)
      else
        append('$', selected)
      endif
      noautocmd normal! G$
    else
      setcmdline(selected)
      redraw
    endif
  enddef

  def _promptGoForward()
    var p = this.GetPrompt()
    const column = min([strchars(p.text), p.column + 1])
    if column != p.column
      p.column = column
      this.SetPrompt(p)
    endif
  enddef

  def _promptGoBackward()
    var p = this.GetPrompt()
    const column = max([0, p.column - 1])
    if column != p.column
      p.column = column
      this.SetPrompt(p)
    endif
  enddef

  def _promptGoHead()
    var p = this.GetPrompt()
    if p.column != 0
      p.column = 0
      this.SetPrompt(p)
    endif
  enddef

  def _promptGoTail()
    var p = this.GetPrompt()
    const column = strchars(p.text)
    if p.column != column
      p.column = 0
      this.SetPrompt(p)
    endif
  enddef

  def _promptDeleteChar()
    var p = this.GetPrompt()
    var text = p.SplitAtColumn()
    if text[0] ==# ''
      return
    endif
    text[0] = text[0]->strcharpart(0, strchars(text[0]) - 1)
    p.column  = p.column - 1
    p.text = text[0] .. text[1]
    this.SetPrompt(p)
  enddef

  def _promptDeleteWord()
    var p = this.GetPrompt()
    if p.column != 0
      var text = p.SplitAtColumn()
      text[0] = text[0]->substitute('\<\w\+\s*$', '', '')
      p.text = text[0] .. text[1]
      p.column = strchars(text[0])
      this.SetPrompt(p)
    endif
  enddef

  def _promptDeleteToHead()
    var p = this.GetPrompt()
    if p.column != 0
      p.text = p.SplitAtColumn()[1]
      p.column = 0
      this.SetPrompt(p)
    endif
  enddef

  def _actionNop()
    # No operation
  enddef
endclass

const ff = FF.new()

export def Select()
  if getcmdtype() ==# '' && getcmdwintype() ==# ''
    Error('Not in command-line or cmdwin')
    return
  endif
  ff.Setup()
enddef

export def MapAction(key: string, actions: list<string>)
  ff.MapAction(key, actions)
enddef

export def UnmapAction(key: string)
  ff.UnmapAction(key)
enddef

export def SetDefaultMappings()
  ff.MapAction('<CR>', ['accept'])
  ff.MapAction('<C-f>', ['go-forward'])
  ff.MapAction('<C-b>', ['go-backward'])
  ff.MapAction('<C-a>', ['go-head'])
  ff.MapAction('<C-e>', ['go-tail'])
  ff.MapAction('<C-h>', ['delete-character'])
  ff.MapAction('<BS>', ['delete-character'])
  ff.MapAction('<Del>', ['delete-character'])
  ff.MapAction('<C-w>', ['delete-word'])
  ff.MapAction('<C-u>', ['delete-to-head'])
  ff.MapAction('<C-p>', ['select-prev-item'])
  ff.MapAction('<C-k>', ['select-prev-item'])
  ff.MapAction('<C-n>', ['select-next-item'])
  ff.MapAction('<C-j>', ['select-next-item'])
  ff.MapAction('<C-l>', ['redraw'])
enddef


# Emit autocommand for user configuration initializations.
augroup plugin-cmdhistory-dummy
  autocmd!
  autocmd User cmdhistory-initialize :
augroup END

doautocmd User cmdhistory-initialize

augroup plugin-cmdhistory-dummy
  autocmd!
augroup END
augroup! plugin-cmdhistory-dummy
