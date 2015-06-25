" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexTest.vim
" Last Modified: 2013-04-11
" Author: Andrey Gavrikov 
" Maintainers: 
"

if exists("g:loaded_apexTest") || &compatible
  finish
endif
let g:loaded_apexTest = 1

let s:ALL = '*ALL*'

" run test using apexTooling
"Param: reportCoverage: 'reportCoverage' (means load lines report), anything
"				        else means do not load lines coverage report
"Params: (optional)
" Param 1: [optional] mode name: ['meta-testAndDeploy', 'meta-checkOnly', 'tooling-sync', 'tooling-async']
" Param 2: [optional] classname[.methodname][,classname[.methodname]]
" Param 3: [optional] destination project name, must match one of .properties file with
"		login details
function! apexTest#runTest(reportCoverage, bang, ...)
	let filePath = expand("%:p")

	let modeName = a:0 > 0? a:1 : 'meta-testAndDeploy'
	let testsToRun = a:0 > 1? a:2 : ''
	let projectName = a:0 > 2? a:3 : ''

    let attributes = {}
    
    if empty(testsToRun)
        call apexUtil#warning("Please specify test(s) to run or * to run all unpackaged tests in the Org")
        return
    endif    
    let attributes['testsToRun'] = testsToRun

	let isCheckOnly = 'meta-checkOnly' == modeName
    let attributes['checkOnly'] = isCheckOnly
    

    if modeName == 'tooling-sync'
        let attributes['tooling'] = 'sync'
    elseif modeName == 'tooling-async'
        let attributes['tooling'] = 'async'
    endif

    " check if classNames contains something like: MyClass.method1
    let l:hasMethodName = (testsToRun  =~? '\w\.\w\w*')

    if l:hasMethodName && (modeName !~ '^tooling-async')
        if modeName =~ '^meta-' && !isCheckOnly
            call apexUtil#warning('Specific method test with Metadata API is experimental and only supported in "checkOnly" mode.')
            if 'y' !~# apexUtil#input('Switch to "meta-checkOnly" and continue? [Y/n]: ', 'YyNn', 'y')
                return
            endif

            let attributes['checkOnly'] = 1
        endif    
        if modeName == 'tooling-sync'
            call apexUtil#warning('Specific method test with Tooling API is only supported in "async" mode.')
            if 'y' !~# apexUtil#input('Switch to "tooling-async" and continue? [Y/n]: ', 'YyNn', 'y')
                return
            endif

            let attributes['tooling'] = 'async'
        endif    

    endif

    call apexTooling#deployAndTest(filePath, attributes, projectName, a:reportCoverage, a:bang)

endfunction

" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
"
function! apexTest#completeParams(arg, line, pos)
	let l = split(a:line[:a:pos-1], '\%(\%(\%(^\|[^\\]\)\\\)\@<!\s\)\+', 1)
	let command = 'ApexTest'
	if a:line =~ "^ApexTestWithCoverage"
		let command = 'ApexTestWithCoverage'
	endif
	let n = len(l) - index(l, command) - 2
	"echomsg 'arg='.a:arg.'; n='.n.'; pos='.a:pos.'; line='.a:line
	let funcs = ['s:listModeNames', 's:listClassNames', 's:listMethodNames', 'apex#listProjectNames']
	if n >= len(funcs)
		return ""
	else
		return call(funcs[n], [a:arg, a:line, a:pos])
endfunction	

function! apexTest#completeClassNames(arg, line, pos)
	return call('s:listClassNames', [a:arg, a:line, a:pos])
endfunction	


" list classes that contain 'testMethod' token for argument auto-completion
function! s:listClassNames(arg, line, pos)
	let projectSrcPath = apex#getApexProjectSrcPath()
	
	let fullPaths = apexOs#glob(projectSrcPath . "**/*.cls")
	let candidates = []
	for fullName in fullPaths
		"check if this class contains testMethod
		if len(apexUtil#grepFile(fullName, 'testMethod\|@isTest')) > 0
			let fName = apexOs#splitPath(fullName).tail
			let fName = fnamemodify(fName, ":r") " remove .cls
			"take into account file prefix which user have already entered
			if 0 == len(a:arg) || match(fName, a:arg) >= 0 
				call add(candidates, fName)
			endif
		endif
	endfor
	return apexUtil#commandLineComplete(a:arg, a:line, a:pos, candidates)
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
	let candidates = [s:ALL]
	for lineNum in apexUtil#grepFileLineNums(filePath, '\<testmethod\>\|@\<isTest\>')
		let methodName = s:getMethodName(filePath, lineNum - 1)
		if len(methodName) > 0
			call add(candidates, methodName)
		endif	
	endfor
	return apexUtil#commandLineComplete(a:arg, a:line, a:pos, candidates)
endfunction	

function! s:listModeNames(arg, line, pos)
	let candidates = ['meta-testAndDeploy', 'meta-checkOnly', 'tooling-sync', 'tooling-async']
	return apexUtil#commandLineComplete(a:arg, a:line, a:pos, candidates)
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
	
	let keyword = "testMethod"
	let rangeStart = match(text, '\c\<testMethod\>')
	if rangeStart < 0
		let keyword = "@isTest"
		let rangeStart = match(text, '\c@\<isTest\>')
	endif
	
	if rangeStart >=0 
		let rangeStart += len(keyword)
		" from here we can look for first '('
		let bracketPos = match(text, '(', rangeStart)
		let curlyBracketPos = match(text, '{', rangeStart)
		if curlyBracketPos < bracketPos
			"this is most likely class name, not method name
			return ""
		else
			if bracketPos > 2
				let index = bracketPos - 1
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
	endif
		
	return apexUtil#trim(methodName)
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

