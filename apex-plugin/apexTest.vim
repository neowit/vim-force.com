" File: apexTest.vim
" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Version: 0.1
" Last Modified: 2013-04-11
" Copyright: Copyright (C) 2010-2013 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
if exists("g:loaded_apexTest") || &compatible
  finish
endif
let g:loaded_apexTest = 1

" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
"
function! ApexTestCompleteParams(arg, line, pos)
	let l = split(a:line[:a:pos-1], '\%(\%(\%(^\|[^\\]\)\\\)\@<!\s\)\+', 1)
	let n = len(l) - index(l, 'ApexTest') - 2
	"echomsg 'arg='.a:arg.'; n='.n.'; pos='.a:pos.'; line='.a:line
	let funcs = ['s:listClassNames', 's:listMethodNames', 'ListProjectNames']
	return call(funcs[n], [a:arg, a:line, a:pos])
endfunction	

" list classes that contain 'testMethod' token for argument auto-completion
function! s:listClassNames(arg, line, pos)
	let projectSrcPath = apex#getApexProjectSrcPath()
	
	let fullPaths = apexOs#glob(projectSrcPath . "**/*.cls")
	let res = []
	for fullName in fullPaths
		"check if this class contains testMethod
		if len(apexUtil#grepFile(fullName, 'testmethod')) > 0
			let fName = apexOs#splitPath(fullName).tail
			let fName = fnamemodify(fName, ":r") " remove .cls
			"take into account file prefix which user have already entered
			if 0 == len(a:arg) || match(fName, a:arg) >= 0 
				call add(res, fName)
			endif
		endif
	endfor
	return res
endfunction	

" using name of the class selected in previous argument list names of all
" 'testMethod'-s
" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
function! s:listMethodNames(arg, line, pos)
	"figure out current class name
	let l = split(a:line[:a:pos-1], '\%(\%(\%(^\|[^\\]\)\\\)\@<!\s\)\+', 1)
	let className = l[1]
	let projectSrcPath = apex#getApexProjectSrcPath()
	let filePath = apexOs#joinPath([projectSrcPath, 'classes', className.'.cls'])
	let res = []
	for lineNum in apexUtil#grepFile(filePath, '\<testmethod\>')
		let methodName = s:getMethodName(filePath, lineNum - 1)
		if len(methodName) > 0
			call add(res, methodName)
		endif	
	endfor

	return res
endfunction	

" Using given file name and starting from lineNum try to identify method name
" assuming that this is the last word before '('
" Args:
" filePath - full class file path
" lineNum - start search from given line
function! TEST(lineNum)
	echo s:getMethodName('/Users/andrey/eclipse.workspace/Sforce - SFDC Experiments/vim-force.com/src/classes/MyClassTest.cls', a:lineNum)
endfunction
function! s:getMethodName(filePath, lineNum)
	"echoerr "filePath=".a:filePath."; .lineNum=".a:lineNum
	let methodName = ''
	let fileLines = readfile(a:filePath, '' , a:lineNum + 6)
	let fileLines = fileLines[a:lineNum :]
	"we are only interested in few lines "starting from the line a:lineNum
	let text =  ''
	for line in fileLines
		let text = text . ' ' . line
	endfor
	
	let rangeStart = match(text, '\c\<testmethod\>')
	if rangeStart >=0 
		let rangeStart += len('testmethod')
		" from here we can look for first '('
		let bracketPos = match(text, '(', rangeStart)
		if bracketPos > 2
			let index = bracketPos - 2 
			" found '(' now first word on the left will be method name
			while 1
				let chr = text[index]
				if chr =~ '\w'
				"echoerr "chr=".chr
					let methodName = chr . methodName
				elseif len(methodName) > 0 || index < 1
					break
				endif
				let index -= 1
			endwhile
		endif	
	endif
		
	return methodName
endfunction

" Return: list of line numbers where 'expr' was found
"		if nothing found then empty list []
function! s:grepFile(fileName, expr)
	let currentQuickFix = getqflist()
	let res = []
	
	try
		let exprStr =  "noautocmd vimgrep /\\c".a:expr."/j ".fnameescape(a:fileName)
		exe exprStr
		"expression found
		"get line numbers from quickfix
		for qfLine in getqflist()
			call add(res, qfLine.lnum)
		endfor	
		
	"catch  /^Vim\%((\a\+)\)\=:E480/
	catch  /.*/
		"echomsg "expression NOT found" 
	endtry
	
	" restore quickfix
	call setqflist(currentQuickFix)
	
	return res
endfunction
