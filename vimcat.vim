" Copyright (c) 2014-2015, Chris Hixon 
" Copyright (c) 2008, Matthew J. Wozniski
" All rights reserved.
"
" Redistribution and use in source and binary forms, with or without
" modification, are permitted provided that the following conditions are met:
" * Redistributions of source code must retain the above copyright
" notice, this list of conditions and the following disclaimer.
" * Redistributions in binary form must reproduce the above copyright
" notice, this list of conditions and the following disclaimer in the
" documentation and/or other materials provided with the distribution.
" * The names of the contributors may not be used to endorse or promote
" products derived from this software without specific prior written
" permission.
"
" THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER ``AS IS'' AND ANY
" EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
" WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
" DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY
" DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
" (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
" LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
" ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
" (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
" SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
"
" AnsiHighlight: Allows for marking up a file, using ANSI color escapes when
" the syntax changes colors, for easy, faithful reproduction.
" Author: Matthew Wozniski (mjw@drexel.edu)
" Date: Fri, 01 Aug 2008 05:22:55 -0400
" Version: 1.0 FIXME
" History: FIXME see :help marklines-history
" License: BSD. Completely open source, but I would like to be
" credited if you use some of this code elsewhere.
"
" This version contains modifications by Chris Hixon:
" - Optimizations
" - Modified for FIFO communication for output and status ("more","done")
" - Rewrote ANSI generation code, added all attributes (italic, standout,
"   underline, etc.)
" - Handle default fg+bold/bg via Normal highlight item
" - Handle tabs and special characters, matching vim screen columns (via virtcol)
"   (downside: slows down things quite a bit)
" - Rewrote to better handle unicode/multibyte, linebreaks
" - Fixed issues with linebreak: jusification of text in cells before/after
"   break, added showbreak text
" - Added line numbering (&number, &numberwidth)
" TODO: parse highlight for @ entry (for showbreak text)
" FIXME: there are some assumptions in this code. there may be unhandled cases
" where text should not displayed (or perhaps displayed truncated, etc.)
" need to look into folding, concealing, and other ways text might be hidden.
" the main assumption is strwidth(char) <= virtcol_calculated_width(char)


" Turn off vi-compatible mode, unless it's already off
if &cp
  set nocp
endif

let s:type = 'cterm'
if &t_Co == 0
  let s:type = 'term'
endif

" Converts info for a highlight group to a string of ANSI color escapes
function! s:GroupToAnsi(groupnum)
  if ! exists("s:ansicache")
    let s:ansicache = {}
  endif

  let groupnum = a:groupnum

  if has_key(s:ansicache, groupnum)
    return s:ansicache[groupnum]
  endif

  let it = synIDattr(groupnum, 'italic', s:type)
  let ul = synIDattr(groupnum, 'underline', s:type)
  let rv = synIDattr(groupnum, 'reverse', s:type)
  let iv = synIDattr(groupnum, 'inverse', s:type)
  let so = synIDattr(groupnum, 'standout', s:type)
  let bd = synIDattr(groupnum, 'bold', s:type)

  let fg = synIDattr(groupnum, 'fg', s:type)
  if fg < 0 || strlen(fg) == 0
    let fg = s:default_fg
    let bd = s:default_bd || bd
  endif

  let bg = synIDattr(groupnum, 'bg', s:type)
  if bg < 0 || strlen(bg) == 0
    let bg = s:default_bg
  endif

  let retv = "\<Esc>[0"

  if bd
    let retv .= ";1"
  endif

  if it
    let retv .= ";3"
  endif

  if ul
    let retv .= ";4"
  endif

  if rv || so || iv
    let retv .= ";7"
  endif

  if fg >= 0
    if fg < 8
      let retv .= ";3" . fg
    elseif fg < 16                "use aixterm codes
      let retv .= ";9" . (fg - 8)
    else                          "use xterm256 codes
      let retv .= ";38;5;" . fg
    endif
  else
    let retv .= ";39"
  endif

  if bg >= 0
    if bg < 8
      let retv .= ";4" . bg
    elseif bg < 16                "use aixterm codes
      let retv .= ";10" . (bg - 8)
    else                          "use xterm256 codes
      let retv .= ";48;5;" . bg
    endif
  else
    let retv .= ";49"
  endif

  let retv .= "m"

  let s:ansicache[groupnum] = retv

  return retv
endfunction

function! AnsiHighlight(data_fifo, status_fifo)

  let options = {}
  if exists("g:vimcat_options")
    let options = g:vimcat_options
  endif

  let delete_chars = '' 
  if has_key(options, 'delete_chars')
    let delete_chars = options['delete_chars']
  endif

  let pack_empty_lines = '' 
  if has_key(options, 'pack_empty_lines')
    let pack_empty_lines = options['pack_empty_lines']
  endif

  let hlID_Normal = hlID('Normal')
  let hlID_SpecialKey = hlID('SpecialKey')
  let hlID_NonText = hlID('NonText')
  let hlID_LineNr = hlID('LineNr')

  let s:default_fg = synIDattr(hlID_Normal, "fg")
  if strlen(s:default_fg) == 0
    let s:default_fg = -1
  endif
  let s:default_bg = synIDattr(hlID_Normal, "bg")
  if strlen(s:default_bg) == 0
    let s:default_bg = -1
  endif
  let s:default_bd = synIDattr(hlID_Normal, "bold")

  let normal = s:GroupToAnsi(hlID_Normal)
  let special = s:GroupToAnsi(hlID_SpecialKey)
  let nontext = s:GroupToAnsi(hlID_NonText)
  let number = s:GroupToAnsi(hlID_LineNr)

  let reset = "\<Esc>[0;39;49m"
  let clear_r = "\<Esc>[K"

  let do_showbreak = &wrap && strlen(&showbreak)
  let do_linebreak = &wrap && &linebreak
  let has_strwidth = exists('*strwidth')
  let showbreak_len = has_strwidth ? strwidth(&showbreak) : 0

  let wwidth = winwidth(0)
  let num_lines = line('$')

  if &number
    let gw = max([1 + strlen(printf("%d", num_lines)), &numberwidth]) " gutter width
    let start_col = gw " display column of first char
    let w1 = wwidth - gw " display width of first line
    if stridx(&cpoptions, 'n') >= 0 " wrapped line goes into gutter
      let w2 = wwidth " display width of wrapped line
      let gpad = '' " gutter padding of wrapped line
    else " wrapped line doesn't go into gutter
      let w2 = w1
      let gpad = repeat(" ", gw)
    endif
  else
    let start_col = 0
  endif

  let output_lines = []
  let num_output_lines = 0 
  let empty_lines = 0

  for lnum in range(1, num_lines)

    " Hopefully fix highlighting sync issues
    exe "norm! " . lnum . "G$"

    let line = getline(lnum)

    let last_hl = -1 " set to invalid/impossible synID
    let last_byte_offset = 0 " byte offset of last char 
    let char_offset = 1 " char offset of next char
    let output = ""
    let outcol = start_col 
    let byte_offset = 0

    while 1
      let byte_offset = byteidx(line, char_offset)
      if byte_offset < 0
        break
      endif
      let char = strpart(line, last_byte_offset, byte_offset - last_byte_offset)
      let width = virtcol([lnum, last_byte_offset + 1]) - outcol
      let hl = -1
      if char == "\t"
        let out = repeat(" ", width)
      elseif stridx(delete_chars, char) >= 0 
        let out = ''
      elseif width < 2 " some assumptions here
        let out = char
        " note: not handling case where strwidth(char) > width (can this happen? hidden? folded?)
      else
        let out = strtrans(char)
        if out != char
          let hl = hlID_SpecialKey
        endif

        " handle linebreak, showbreak, numbering, and other padding cases,
        " only if strwidth() is available 
        if has_strwidth 
          let outw = strwidth(out)
          if &number " handle the (number) gutter
            if outw < width
              if do_linebreak && (outcol + width == w1 || (outcol > w1 && (outcol + width - w1) % w2 == 0))
                let out .= repeat(" ", width - outw)
              elseif do_showbreak && (outcol == w1 || (outcol > w1 && (outcol - w1) % w2 == 0))
                let output .= gpad . nontext . &showbreak
                let last_hl = hlID_NonText
                let out = repeat(" ", width - showbreak_len - outw) . out
              else
                let out = repeat(" ", width - outw) . out
              endif
            endif
          else " simpler version of above, no gutter
            if outw < width
              if do_linebreak && (outcol + width) % wwidth == 0
                let out .= repeat(" ", width - outw)
              elseif do_showbreak && outcol > 0 && outcol % wwidth == 0
                let output .= nontext . &showbreak
                let last_hl = hlID_NonText
                let out = repeat(" ", width - showbreak_len - outw) . out
              else
                let out = repeat(" ", width - outw) . out
              endif
            endif
          endif
        endif
      endif

      if hl < 0
        let hl = synIDtrans(synID(lnum, last_byte_offset + 1, 1))
      endif
      if hl != last_hl
        let output .= s:GroupToAnsi(hl)
        let last_hl = hl
      endif

      let output .= out 
      let outcol += width
      let last_byte_offset = byte_offset
      let char_offset += 1 
    endwhile

    if empty(output)
      let empty_lines += 1 
    else
      let empty_lines = 0 
    endif

    if !pack_empty_lines || empty_lines < 2
      if &number
        let output = number . printf('%'.(gw-1).'d ', lnum) . output
      endif

      let output .= normal . clear_r " reset to normal and clear to the right
      let output_lines += [output]
      let num_output_lines += 1 
    endif

    " send collected output every N lines, and on last line
    if lnum == num_lines || num_output_lines >= 50
      if lnum == num_lines
        let output_lines[-1] .= reset " add a reset to last line
      endif
      if writefile(output_lines, a:data_fifo) < 0
        call writefile(["done"], a:status_fifo)
        return
      endif
      if writefile([lnum == num_lines ? "done" : "more"], a:status_fifo) < 0
        return
      endif
      let output_lines = []
      let num_output_lines = 0 
    endif
  endfor

endfunction

" vim: sw=2 sts=2 et ft=vim
