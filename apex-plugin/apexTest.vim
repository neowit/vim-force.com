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

let s:ALL = '*ALL*'
" Params:
" Param 1: [optional] mode name: ['testAndDeploy', 'checkOnly']
" Param 2: [optional] class name
" Param 3: [optional] method name
" Param 4: [optional] destination project name, must match one of .properties file with
"		login details
function! apexTest#runTest(...)
	let modeName = a:0 > 0? a:1 : 'testAndDeploy'
	let className = a:0 > 1? a:2 : ''
	let methodName = a:0 > 2? a:3 : ''
	let projectName = a:0 > 3? a:4 : ''

	let projectSrcPath = apex#getApexProjectSrcPath()

	let filePath = ''
	if strlen(className) > 0
		let filePath = apexOs#joinPath([projectSrcPath, 'classes', className.'.cls'])
	endif

	if strlen(methodName) > 0 && s:ALL != methodName
		call apex#MakeProject(filePath, 'onefile', ['checkOnly', className, methodName], projectName)
	elseif strlen(className) > 0
		call apex#MakeProject(filePath, 'onefile', [modeName, className], projectName)
	else 
		call apex#MakeProject(filePath, 'modified', [modeName], projectName)
	endif

endfunction
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
	let funcs = ['s:listModeNames', 's:listClassNames', 's:listMethodNames', 'ListProjectNames']
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
	let className = l[2] " class name is second parameter
	let projectSrcPath = apex#getApexProjectSrcPath()
	let filePath = apexOs#joinPath([projectSrcPath, 'classes', className.'.cls'])
	let res = [s:ALL]
	for lineNum in apexUtil#grepFile(filePath, '\<testmethod\>')
		let methodName = s:getMethodName(filePath, lineNum - 1)
		if len(methodName) > 0
			call add(res, methodName)
		endif	
	endfor

	return res
endfunction	

function! s:listModeNames(arg, line, pos)
	return ['testAndDeploy', 'checkOnly']
endfunction	

" Using given file name and starting from lineNum try to identify method name
" assuming that this is the last word before '('
" Args:
" filePath - full class file path
" lineNum - start search from given line
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

" check if current line is a unit test failure report line
"
" Unit Test falure looks like this:
" Test failure, method: x1.MyClassTest.test1 -- System.AssertException: Assertion Failed: expected this test to fail stack Class.x1.MyClassTest.test1: line 4, column 1
" or, without namespace
" Test failure, method: MyClassTest.test1 -- System.AssertException: Assertion Failed: expected this test to fail stack Class.MyClassTest.test1: line 4, column 1
"
" Return:  dictionary: see :help setqflist()
"         {
"			filename: file name relatively project/src folder, 
"				e.g. "classes/MyClass.cls"
"			lnum: line number in the file
"			col:  column number
"			text: description of the error
"         }
"
function! apexTest#parseUnitTestFailure(text)
	let text = a:text
	let errLine = {}
	let lineAndColumnPair = []
	let className = ''
	if text =~ 'Test failure'
		" try to find line/col like this ": line 4, column 1"
		let lineNumIndex = match(text, ': line ')
		if lineNumIndex > 0
			let coordinateText = strpart(text, lineNumIndex + len(': line '))
			"coordinateText = "4, column 1"
			let lineAndColumnPair = split(coordinateText, ", column ")
		endif
		" extract class name from part which looks like this:
		" stack Class.MyClassTest.test1: line 4, column 1 
		let classNameStart = match(text, 'stack Class.')
		if classNameStart > 0
			let classNameStart = classNameStart + len('stack Class.')
			let classNameEnd = match(text, ':', classNameStart)
			let classNamePart = strpart(text, classNameStart, classNameEnd-classNameStart)
			let classNameParts = split(classNamePart, '\.')
			if len(classNameParts) >2
				" ['x1', 'MyClassTest', 'test1'], i.e. with namespace
				let className = classNameParts[1]
			else
				" ['MyClassTest', 'test1']
				let className = classNameParts[0]
			endif
		endif
		
	endif
	if len(lineAndColumnPair) >1 && len(className) > 0
		let errLine.lnum = lineAndColumnPair[0] " line
		let errLine.col = lineAndColumnPair[1] " column
		let errLine.filename = 'classes/'.className. '.cls'
		let errLine.text = text
	endif

	return errLine

endfunction	

"
" 
" Return: path to ant error log
" Param 1: project descriptor
" Param 2: list [] of other params
"		0:
"		  'testAndDeploy' - run tests in all files that contain 'testMethod' and if
"					successful then deploy
"		  'runTestOnly' - run tests but do not deploy
"		1: 
"		  className - if provided then only run tests in the specified class
"		2:
"		  methodName - if provided then only run specified method in the class
"		  provided as 1:
function! apexTest#prepareFilesAndRunTests(projectDescriptor, params)
	let projectName = a:projectDescriptor.project
	let preparedSrcPath = a:projectDescriptor.preparedSrcPath
	let projectPath = apexOs#splitPath(preparedSrcPath).head
	
	let params = a:params
	let checkOnly = params[0] " testAndDeploy | checkOnly
	let classNames = []
	if len(params) > 1
		" need to run tests only in the specified class
		let classNames = [ params[1] ]
		if len(params) > 2 "looks like we need to run only specific method name
			let methodName = params[2]
			let fClassPath = apexOs#joinPath([preparedSrcPath, 'classes', classNames[0].'.cls'])
			call s:disableAllTestMethodsExceptOne(fClassPath, methodName)
			let checkOnly = 'checkOnly' " when we mess with class code we can not afford actual deployment
		endif
	else
		let files = apexOs#glob(projectPath . "**/*.cls")
		for fClassFullPath in files
			let fClassName = apexOs#splitPath(fClassFullPath).tail
			" check if this file contains testMethod
			if len(apexUtil#grepFile(fClassFullPath, 'testmethod')) > 0
				"prepare just file name, without extension
				"remove .cls
				let fClassName = strpart(fClassName, 0, len(fClassName) - len('.cls'))
				let classNames = add(classNames, fClassName)
			else
				"echomsg "  ".fClassName." does not contain test methods. SKIP"
			endif
		endfor
	endif
	if len(classNames) >0
		call apexAnt#askLogType()
		return apexAnt#runTests(projectName, projectPath, classNames, checkOnly)
	else
		call apexUtil#warning("No test methods in files scheduled for deployment. Use :ApexDeploy to deploy without tests.")
	endif
	return ''

endfunction

" in the class specified by given path put 'return;' at the beginning of all
" methods except the one specified
" Args:
" fClassPath - full path to class file
" methodName - name of testMethod - the only methid which needs to stay
" enabled
function! s:disableAllTestMethodsExceptOne(fClassPath, methodName)
	let fClassPath = a:fClassPath
	let methodName = a:methodName
	
	let lineNumbers = apexUtil#grepFile(fClassPath, 'testmethod')

	if len(lineNumbers) > 0

		let outputLines = []
		let rangeStart = -1
		let lineNum = -1
		for line in readfile(fClassPath) 
			let lineNum += 1
			if rangeStart < 0
				let rangeStart = match(line, '\c\<testmethod\>')
			endif
			if rangeStart >=0 
				"check if this is the method which we need to leave enabled
				if methodName == s:getMethodName(fClassPath, lineNum)
					let rangeStart = -1
					call add(outputLines, line)
					continue " skip this method
				endif
				"try to find first {
				let bracketPos = match(line, '{', rangeStart)
				if bracketPos >= 0
					"echo "was=".line
					let line = strpart(line, 0, bracketPos+1) . 'return;'. strpart(line, bracketPos + 1)
					"echo "now=".line
					let rangeStart = -1 " assuming that there is just one method definition per line
				else
					let rangeStart = 0 " in the next line need to start from the beginning of the line
				endif
			endif

			call add(outputLines, line)
		endfor	
	endif
	"finally write resulting file
	call writefile(outputLines, fClassPath)
	
endfunction
