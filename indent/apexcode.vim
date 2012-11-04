" File: apexcode.vim
" Author: Andrey Gavrikov 
" Version: 0.1
" Last Modified: 2012-11-05
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" indent config for apex code files

if exists("b:did_indent")
	    finish
	endif
let b:did_indent = 1


runtime! indent/java.vim
