# cmdhistory.vim

This is a Vim plugin to select command-line history on command-line and command-line window.


## Requirements

- Vim 9.1.1230 or later.
- Neovim v0.11.0 or later.


## Example configuration

In your .vimrc:

```vim
cnoremap <C-o> <Cmd>call cmdhistory#select()<CR>

augroup setup-cmdhistory-plugin-for-cmdwin
  autocmd!
  autocmd CmdWinEnter * nnoremap <buffer> / <Cmd>call cmdhistory#select()<CR>
  autocmd User cmdhistory-initialize call s:setup_cmdhistory()
augroup END

function s:setup_cmdhistory()
  " Set plugin default mappings.
  call cmdhistory#set_default_mappings()

  " Accept the present item with <Tab> key.
  call cmdhistory#map_action('<Tab>', ['accept'])
endfunction
```
