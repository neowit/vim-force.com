" File: apexExecuteSnippet.vim
" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Maintainers: 
" Last Modified: 2014-11-27
"
" apexExecuteSnippet.vim - support for calling 'executeAnonymous' &
" 'soqlQuery' commands
"
if exists("g:loaded_apexExecuteSnippet") || &compatible
	  finish
endif
let g:loaded_apexExecuteSnippet = 1

let s:lastExecuteAnonymousFilePath = ''
"execute piece of code via executeAnonymous
"This function can accept visual selection or whole buffer and
"runs executeAnonymous on that code
"Args:
"Param: filePath - file which contains the code to be executed
function apexExecuteSnippet#run(method, filePath, ...) range
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectName = projectPair.name
	if a:0 > 0 && len(a:1) > 0
		let projectName = apexUtil#unescapeFileName(a:1)
	endif
	
	let totalLines = line('$') " last line number in current buffer
	let lines = getbufline(bufnr("%"), a:firstline, a:lastline)

	if len(lines) < totalLines
		"looks like we are working with visual selection, not whole buffer
		let lines = s:getVisualSelection()
		"with visual selection we often select lines which are commented out
		"inside * block
		" pre-process lines - remove comment character '*'
		let processedLines = []
		for line in lines
			" remove * if it is first non-space character on the line
			let line = substitute(line, "^[ ]*\\*", "", "")
			call add(processedLines, line)
		endfor
		let lines = processedLines
	endif
	
	if !empty(lines)
		let codeFile = tempname()
		if 'executeAnonymous' == a:method
			let s:lastExecuteAnonymousFilePath = codeFile " record file path for future use in executeAnonymousRepeat
		elseif 'soqlQuery' == a:method
			let s:lastSoqlQueryFilePath = codeFile " record file path for future use in executeAnonymousRepeat
		endif
		call writefile(lines, codeFile)
		if 'executeAnonymous' == a:method
			call s:executeAnonymous(a:filePath, projectName, codeFile)
		elseif 'soqlQuery' == a:method
            let l:api = 'Partner'
            if a:0 > 0 && len(a:1) > 0
                let l:api = a:1
            endif
            if a:0 > 1 && len(a:2) > 1
                let projectName = apexUtil#unescapeFileName(a:2)
            else
                let projectName = projectPair.name
            endif
			call s:executeSoqlQuery(a:filePath, l:api, projectName, codeFile)
		endif
	endif
endfunction	

"re-run last block of code executed with ExecuteAnonymous
"Param1: (optional) - project name
function apexExecuteSnippet#repeat(method, filePath, ...)
	let codeFile = s:lastExecuteAnonymousFilePath
	if 'soqlQuery' == a:method
		let codeFile = s:lastSoqlQueryFilePath
	endif
	if len(codeFile) < 1 || !filereadable(codeFile)
		call apexUtil#warning('Nothing to repeat')
		return -1
	endif
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectName = projectPair.name
	if a:0 > 0 && len(a:1) > 0
		let projectName = apexUtil#unescapeFileName(a:1)
	endif
	
	if 'executeAnonymous' == a:method
		call s:executeAnonymous(a:filePath, projectName, codeFile)
	elseif 'soqlQuery' == a:method
        let l:api = 'Partner'
        if a:0 > 0 && len(a:1) > 0
            let l:api = a:1
        endif
        if a:0 > 1 && len(a:2) > 1
            let projectName = apexUtil#unescapeFileName(a:2)
        else
            let projectName = projectPair.name
        endif
		call s:executeSoqlQuery(a:filePath, l:api, projectName, codeFile)
	endif
endfunction

function s:executeAnonymous(filePath, projectName, codeFile)
	call apexLogActions#askLogLevel(a:filePath, 'meta')

	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectPath = projectPair.path
	let l:extraParams = {"codeFile": apexOs#shellescape(a:codeFile)}
	" another org?
	if projectPair.name != a:projectName
		let l:extraParams["callingAnotherOrg"] = "true"
	endif
	let resMap = apexTooling#execute("executeAnonymous", a:projectName, projectPath, l:extraParams, [])
	if exists('g:apex_test_debuggingHeader')
		if "true" == resMap.success
			:ApexLog
		endif
	endif
endfunction	

let s:lastSoqlQueryFilePath = ""
function s:executeSoqlQuery(filePath, api, projectName, codeFile)

	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectPath = projectPair.path
	let outputFilePath = tempname()
	let l:extraParams = {"queryFilePath": apexOs#shellescape(a:codeFile), 'outputFilePath':  apexOs#shellescape(outputFilePath)}
	" another org?
	if projectPair.name != a:projectName
		let l:extraParams["callingAnotherOrg"] = "true"
	endif
    let l:extraParams["api"] = a:api
	let resMap = apexTooling#execute("soqlQuery", a:projectName, projectPath, l:extraParams, [])
	if "true" == resMap.success
        let s:lastSoqlQueryFilePath = a:codeFile
		" load result file if available and show it in a read/only buffer
		if len(apexUtil#grepFile(resMap.responseFilePath, 'RESULT_FILE')) > 0
			execute "view " . fnameescape(outputFilePath)
		endif
	endif
endfunction	

" http://stackoverflow.com/a/6271254
function! s:getVisualSelection()
  let [lnum1, col1] = getpos("'<")[1:2]
  let [lnum2, col2] = getpos("'>")[1:2]
  let lines = getline(lnum1, lnum2)
  let lines[-1] = lines[-1][: col2 - (&selection == 'inclusive' ? 1 : 2)]
  let lines[0] = lines[0][col1 - 1:]
  return lines
endfunction
