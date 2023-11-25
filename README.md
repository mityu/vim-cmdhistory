# cmdhistory.vim

This is a plugin written in Vim9 script to select command history on command-line and command-line window.


## Requirements

Vim 9.0.2129 or later.  Be careful that Vim may crash in prior version.


## Example configuration

```vim
vim9script

cnoremap <C-o> <Cmd>call cmdhistory#Select()<CR>

augroup setup-cmdhistory-plugin-for-cmdwin
  autocmd!
  autocmd CmdWinEnter * nnoremap <buffer> / <Cmd>call cmdhistory#Select()<CR>
  autocmd User cmdhistory-initialize * SetupCmdhistory()
augroup END

def SetupCmdhistory()
  # Set plugin default mappings.
  cmdhistory#SetDefaultMappings()

  # Accept the present item with <Tab> key.
  cmdhistory#MapAction('<Tab>', ['accept'])
enddef
```
