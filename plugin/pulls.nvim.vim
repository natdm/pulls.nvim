if exists('g:loaded_pulls') | finish | endif

" expose vim commands and interface here
" nnoremap <Plug>PlugCommand :lua require(...).plug_command()<CR>

let s:save_cpo = &cpo
set cpo&vim

let g:loaded_pulls = 1

let &cpo = s:save_cpo
unlet s:save_cpo
