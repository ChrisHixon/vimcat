# Vimcat

Vimcat displays colored/highlighted text as it is displayed in Vim, using ANSI escape codes. It supports tabular/column alignment, line numbers, line breaks, unicode, full-width characters, and more.

## Requirements

1. Vim 7.x (may work with earlier versions)
2. Python 2.x, with pty support
3. OS with named pipe (FIFO) support

## Installation

1. Place the Python script 'vimcat' somewhere in your $PATH
2. Place the file 'vimcat.vim' in your vim runtime path, for example, $HOME/.vim/

## Usage

$ vimcat [FILE]...

## Details

Vimcat consists of two parts: a Python script that launches a headless Vim in a pseudo-terminal, and a Vimscript to do the ANSI conversion work inside Vim. Output and signaling between processes takes place via named pipes (FIFOs). This method allows Vim to start outputting converted data without having to finish converting the whole file. This is nice for interactive viewing/paging. This idea is a workaround for Vimscript's limitations which require a slow character by character query for color/highlight information (see :help synID)

## Configuration

Vimcat attempts to output colors and highlighting to mimic Vim's interactive display. Syntax highlighting, colorschemes, and any other relevant options should be configured in your .vimrc file. Alternatively, if $HOME/.vimcatrc exists, it will will override all normal initializations, including .vimrc.

## Credits

The Vimscript portion of the code is based on code from Matthew Wozniski (mjw@drexel.edu).
