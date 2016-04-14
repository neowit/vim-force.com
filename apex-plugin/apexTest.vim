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

let b:projectPair = apex#getSFDCProjectPathAndName(expand("%:p"))
let b:PROJECT_NAME = b:projectPair.name
let b:PROJECT_PATH = b:projectPair.path
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
    elseif modeName == 'testSuites'
        let attributes['tooling'] = 'testSuites'
        call remove(attributes, 'testsToRun')
        let attributes['testSuites'] = testsToRun
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
	"let funcs = ['s:listModeNames', 's:listClassNames', 's:listMethodNames', 'apex#listProjectNames']
	let funcs = ['s:listModeNames', 's:listClassOrMethodNames', 'apex#listProjectNames']
	if n >= len(funcs)
		return ""
	else
		return call(funcs[n], [a:arg, a:line, a:pos])
endfunction	

" if previous character is nothing or ',' then list class names or Test Suite
" names
" if previous character is '.' then take previous word, use it as a class name
" and list method names in that class
" 
" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
function! s:listClassOrMethodNames(arg, line, pos)
    if !empty(a:arg) && a:arg =~ '\w\.\w*$'
        return s:listMethodNames(a:arg, a:line, a:pos)
    elseif a:line =~ " testSuites "
        return s:listTestSuiteNames(a:arg, a:line, a:pos)
    else
        return s:listClassNames(a:arg, a:line, a:pos)
    endif    

endfunction

" list classes that contain 'testMethod' token for argument auto-completion
" arg may look like so
" 
" <Cla>
" <Class.method,>
" <Class.method,Cla>
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
            let l:str = a:arg
            let l:prevStr = '' " stuff which was entered before class name currently being completed

            if len(l:str) > 0
                let l:strings = split(a:arg, ',')
                if a:arg =~ '\w.*,$' " <Something,>
                    let l:prevStr = join(l:strings, ',') . ','
                    let l:str = ''
                else    " <Something,Some>
                    let l:str = l:strings[len(strings)-1]
                    if len(l:strings) > 1
                        " have class names before current
                        let l:prevStr = join(l:strings[0:len(strings)-2], ",") . ","
                    endif    
                endif
            endif

			if 0 == len(l:str) || match(fName, l:str) >= 0 
				call add(candidates, l:prevStr . fName)
			endif
		endif
	endfor
	return apexUtil#commandLineComplete(a:arg, a:line, a:pos, candidates)
endfunction	

" using name of the class selected in previous argument list names of all
" 'testMethod'-s
" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on, all previous class.method pairs removed
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
" originalArg: full text of current parameter
function! s:listMethodNames(arg, line, pos)
    "figure out current class name
    let l:str = a:arg
    let l:prevStr = '' " stuff which was entered before class name currently being completed
    if empty(l:str)
        return []
    endif

    let l:strings = split(a:arg, ',')
    if len(l:strings) > 1
        let l:prevStr = join(l:strings[0:len(l:strings) - 2], ',') . ','
    endif
    let l:lastStr = l:strings[-1]
	
    let l = split(l:lastStr, '\.')

	let className = l[0]
    let methodNameSoFar = len(l) > 1 ? l[1] : ""

	let projectSrcPath = apex#getApexProjectSrcPath()
	let filePath = apexOs#joinPath([projectSrcPath, 'classes', className.'.cls'])
	let candidates = [s:ALL]
    let adddedValues = [] " track added values to avoid duplicates
	for lineNum in apexUtil#grepFileLineNums(filePath, '\<testmethod\>\|@\<isTest\>')
		let methodName = s:getMethodName(filePath, lineNum - 1)
        let l:classMethod = className . '.' . methodName
		if len(methodName) > 0 && index(adddedValues, l:classMethod) < 0
			call add(candidates, l:prevStr . l:classMethod)
            call add(adddedValues, l:classMethod)
		endif	
	endfor
	return apexUtil#commandLineComplete(a:arg, a:line, a:pos, candidates)
endfunction	

function! s:listModeNames(arg, line, pos)
	let candidates = ['meta-testAndDeploy', 'meta-checkOnly', 'tooling-sync', 'tooling-async', 'testSuites']
	return apexUtil#commandLineComplete(a:arg, a:line, a:pos, candidates)
endfunction	
"
" list test suite names for argument auto-completion
" arg may look like so
" 
" <Cla>
" <Class.method,>
" <Class.method,Cla>
function! s:listTestSuiteNames(arg, line, pos)
    let candidates = s:getTestSuiteNames(b:PROJECT_NAME, b:PROJECT_PATH, 0)
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

"depending on the current command set metadata description can be in two
"different formats
function! s:getTestSuiteCacheFile()
	return "testSuites-cache.js"
endfunction

function! s:getTestSuiteCacheFilePath(projectPath)
	return apexOs#joinPath([apex#getCacheFolderPath(a:projectPath), s:getTestSuiteCacheFile()])
endfunction

function! s:getTestSuiteNames(projectName, projectPath, forceLoad)

	let l:testSuitesFilePath = s:getTestSuiteCacheFilePath(a:projectPath)
    " reload test suites list if current cache file is more than 10 seconds
    " old
    let l:timeThreshold = localtime() - 10 " 10 seconds ago

	if !filereadable(l:testSuitesFilePath) || a:forceLoad || getftime(l:testSuitesFilePath) < l:timeThreshold
		silent let res = apexTooling#loadTestSuiteNamesList(a:projectName, a:projectPath, testSuitesFilePath)
		if 'true' != res["success"]
			return []
		endif
	endif
	let l:names = []
	let l:lines = readfile(testSuitesFilePath, '', 1) " assuming test suite names file will never contain more than 1 line

    if len(l:lines) > 0
	    let l:names = eval(l:lines[0])
    endif    
    return l:names
        
endfunction    
