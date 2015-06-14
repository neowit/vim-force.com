" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexUtil.vim
" Author: Andrey Gavrikov 
" Last Modified: 2014-05-06
" Maintainers: 
"
" Various utility methods used by different parts of force.com plugin 
"
if exists("g:loaded_apexUtil") || &compatible
  finish
endif
let g:loaded_apexUtil = 1

if !exists("g:apex_diff_cmd") 
	if has("unix")
		" use Meld by default
		let g:apex_diff_cmd="/usr/bin/meld"
	else
		" echoerr 'please define command for diff tool'
	endif 
endif	

" compare file given as argument a:1 with its version given as a:2
" If a:2 is not specified then compare source file with same file from another
" project, assuming project structure of left and right projects is equal and
" they have common parent folder
function! apexUtil#compareFiles(...)
	let leftFilePath = '' 
	if a:0 >0
		let leftFilePath = a:1
	else
		" use current file
		let leftFilePath = expand("%:p")
	endif	

	if a:0 >1
		let rightFilePath = a:2
	else	
		let rightFilePath = apexUtil#selectCounterpartFromAnotherProject(leftFilePath)
	endif	
	if len(rightFilePath) < 1
		echo 'comparison cancelled'
		return ""
	endif
	
	if executable(g:apex_diff_cmd)
		let scriptPath = shellescape(g:apex_diff_cmd)
		"let command = scriptPath.' '.shellescape(leftFilePath).' '.shellescape(rightFilePath)
		let command = scriptPath.' '.apexOs#shellescape(leftFilePath).' '.apexOs#shellescape(rightFilePath)
		"echo "command=".command
	
		":exe "!".command
		call apexOs#exe(command, 'b')
	else
		" use built-in diff
		:exe "vert diffsplit ".substitute(rightFilePath, " ", "\\\\ ", "g")
	endif
endfunction

" browse to root of another project and call external diff tool on two folders:
" <external diff> current-project/src selected-project/src
function! apexUtil#compareProjects(leftFilePath)
	let leftFile = a:leftFilePath
	
	let projectPair = apex#getSFDCProjectPathAndName(leftFile)
	let leftProjectPath = projectPair.path
	let rootDir = apexOs#splitPath(leftProjectPath).head
	let rightProjectPath = apexOs#browsedir('Please select project to compare with:', rootDir)
	if len(rightProjectPath) < 1
		echo 'comparison cancelled'
		return ""
	endif

	if executable(g:apex_diff_cmd)
		let leftSrcPath = apexOs#joinPath(leftProjectPath, "src")
		let rightSrcPath = rightProjectPath
		if "src" != apexOs#splitPath(rightSrcPath).tail
			let rightSrcPath = apexOs#joinPath(rightProjectPath, "src")
		endif
		let scriptPath = shellescape(g:apex_diff_cmd)

		let command = scriptPath.' '.apexOs#shellescape(leftSrcPath).' '.apexOs#shellescape(rightSrcPath)
		
		call apexOs#exe(command, 'b')
	else
		call apexUtil#error("For project comparison external diff tool must be defined via 'g:apex_diff_cmd' ")
	endif
endfunction

" utility function to display highlighted warning message
function! apexUtil#warning(text)
	echohl WarningMsg
	echomsg a:text
	echohl None 
endfun	
"
" utility function to display highlighted info message
function! apexUtil#info(text)
	echohl Question
	echomsg a:text
	echohl None 
endfun	
"
" utility function to display highlighted error message
function! apexUtil#error(text)
	echohl ErrorMsg
	echomsg a:text
	echohl None
endfun	

function! apexUtil#throw(string) abort
  let v:errmsg = 'vim-force.com: '.a:string
  throw v:errmsg
endfunction


" create Git repo for current Apex project and add files
function! apexUtil#gitInit()
	if !executable('git')
		echomsg 'force.com plugin: Git (http://git-scm.com/) ' .
                \ 'not found in PATH. apexUtil#gitInit() is not available.'
		finish
	endif	

	let filePath = expand("%:p")
	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	let projectPath = projectPair.path
	let projectSrcPath = apex#getApexProjectSrcPath(filePath)
	echo "projectPath=".projectPath
	let supportedFiles = {'labels': 'labels', 'pages': 'page', 'classes' : 'cls', 'triggers' : 'trigger', 'components' : 'component', 'staticresources' : 'resource'}

	let response = input('Init new Git repository at: "'.projectPath.'" [a/y/n]? ')
	if 'y' == response || 'Y' == response || 'a' == response || 'A' == response
		call apexOs#exe("git init '".projectPath."'")
	endif	
	let dirs =keys(supportedFiles)
	for dirName in dirs
		" echo dirName
		let fullPath = apexOs#joinPath([projectSrcPath, dirName])
		if isdirectory(fullPath)
			let fileExtention = supportedFiles[dirName]
			let maskPath = "'".fullPath."/*.".fileExtention."'"
			if  'a' != response && 'A' != response
				let response = input('add files: "'.maskPath.'" [a/y/n]? ')
			endif

			if 'y' == response || 'Y' == response || 'a' == response || 'A' == response
				call apexOs#exe("git add ".maskPath)
			endif	
		else
			" echo fullPath." is not existing directory"
		endif
	endfor	

endfunction
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" compare current version of the file with last version backed up before
" refresh
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! apexUtil#compareWithPreRefreshVersion (apexBackupFolder)
	
	" use current file
	let leftFilePath = expand("%:p")
	let leftFileName = expand("%:t")
	let filePathRelativeProjectFolder = apex#getFilePathRelativeProjectFolder(leftFilePath)

	if len(a:apexBackupFolder) <1
		echoerr "parameter 1: apexBackupFolder is required"
		return
	endif	
	" open folder selection dialogue
	let projectPair = apex#getSFDCProjectPathAndName(leftFilePath)
	let projectPath = projectPair.path
	let projectName = projectPair.name
	let backupRoot = apexOs#joinPath([a:apexBackupFolder, projectName])
	let rightProjectPath = apexOs#browsedir("Select folder from Backup to compare with", backupRoot)

	if len(rightProjectPath) <1
		"cancelled
		return
	endif

	let rightFilePath = apexOs#joinPath(rightProjectPath, filePathRelativeProjectFolder)
	if !filereadable(rightFilePath)
		echohl WarningMsg | echo "file ".rightFilePath." is not readable or does not exist" | echohl None
		return
	endif	
    
	call apexUtil#compareFiles(leftFilePath, rightFilePath)

endfunction	

" using given filepath return path to the same file but in another project
" selected by user via Folder selection dialogue
function! apexUtil#selectCounterpartFromAnotherProject(filePath)
	let leftFile = a:filePath

	let filePathRelativeProjectFolder = apex#getFilePathRelativeProjectFolder(leftFile)

	let projectPair = apex#getSFDCProjectPathAndName(leftFile)
	let rootDir = apexOs#splitPath(projectPair.path).head
	"let rightProjectPath = browsedir("Select Root folder of the Project to compare with", rootDir)
	let rightProjectPath = apexOs#browsedir('Please select project to compare with:', rootDir)

	if len(rightProjectPath) <1 
		" cancelled
		return ""
	endif
	let rightFilePath = apexOs#joinPath([rightProjectPath, filePathRelativeProjectFolder])
	"echo "rightFilePath=".rightFilePath
	return rightFilePath
endfunction

"	@deprecated, use apexOs#hasTrailingPathSeparator instead
function! apexUtil#hasTrailingPathSeparator(filePath)
	return apexOs#hasTrailingPathSeparator(a:filePath)
endfunction	

"	@deprecated, use apexOs#joinPath instead
function! apexUtil#joinPath(filePathList)
	return  apexOs#joinPath(a:filePathList)
endfunction	

function! apexUtil#trim(str)
    return substitute(a:str, '^\s*\(.\{-}\)\s*$', '\1', '')
endfunction

" display menu and return value of selected option
" Param: prompt - e.g. "Select one of following:"
" Param: options - 
"		- list of lists, each sub-list is one menu item
"			each sub-list represents: ['return value', 'display value']
"			[["a","option a"], ["b","option B"], ["default","something else"]]
"		OR
"		- list of values, where each value represents both "value" and "label"
"		   e.g. ['apple', 'orange', 'banana']
" Return: if valid element was selected then "return value" of that element,
"			otherwise value of "default"
function! apexUtil#menu(prompt, options, default)

	" blank line before menu
	echo "\n"

	call apexUtil#info(a:prompt)

	let i = 1
	for elem in a:options
		let item = []
		let isList = (type([]) == type(elem))
		if !isList
			" this is a string value, so use it as 'value' and as 'label'
			let item = [elem, elem]
		else
			let item = elem
		endif	
		let itemText = item[1]
		if item[0] == a:default
			let itemText .= ' *'
		endif
		echo i.". ".itemText
		let i += 1
	endfor

	let res = 'nothing'
	while len(res) > 0
		let res = input('Type number and <Enter> (empty defaults to "'.a:default.'"): ')
		if res > 0 && res <= len(a:options)
			echo ""
			if isList
				return a:options[res-1][0]
			else
				return a:options[res-1]
			endif	
		endif
	endwhile
	echo ""
	return a:default
endfunction	

" Args:
" prompt - text shown to user
" options - string with the list of accepted answers
"			e.g.: 'YynN'
" default - if provided then this option is used instead of blank selection
"			if Not provided then prompt will be repeated
" Return: - selected option or default [if provided default is not blank]		
"
" Usage example:
"let overwrite = apexUtil#input("Overwrite package.xml [y/N]? ", "YynN", "N") ==? 'y'
"
function! apexUtil#input(prompt, options, default)
	while 1
		echohl WarningMsg
		let res = input(a:prompt)
		echohl None 
		if len(res) < 1 && strlen(a:default) > 0
			return a:default
		elseif len(res) >0 && a:options =~# res " check if given answer is allowed
			return res
		endif
	endwhile
endfunction

" check if file contains given regular expression and return Line Numbers
" containing this expression
" Param: filePath - full path to the file
" Param: expr - regular expression
" Param: options - string which contains modifiers
"		'Q' - do not preserve quickfix, i.e. populate it with search result
" Return: list of line numbers where 'expr' was found
"		if nothing found then empty list []
function! apexUtil#grepFileLineNums(filePath, expr, ...)
	let currentQuickFix = getqflist()
	let lines = []
	
	try
		let exprStr =  "noautocmd vimgrep /\\c".a:expr."/j ".fnameescape(a:filePath)
		exe exprStr
		"expression found
		"get line numbers from quickfix
		for qfLine in getqflist()
			call add(lines, qfLine.lnum)
			"call add(lines, qfLine.text)
		endfor	
	"catch  /^Vim\%((\a\+)\)\=:E480/
	catch  /.*/
		"echomsg "apexUtil#grepFileLineNums: expression NOT found: ". exprStr
	endtry
	
	" restore quickfix
	if a:0 < 1 || a:1 !~# 'Q'
		call setqflist(currentQuickFix)
	endif
	
	return lines
endfunction

" check if file contains given regualr expression
" Param: filePath - full path to the file
" Param: expr - regular expression
" Param: options - string which contains modifiers
"		'Q' - do not preserve quickfix, i.e. populate it with search result
" Return: list of lines where 'expr' was found
"		if nothing found then empty list []
function! apexUtil#grepFile(filePath, expr, ...)
	let currentQuickFix = getqflist()
	let lines = []
	
	try
		let exprStr =  "noautocmd vimgrep /\\c".a:expr."/j ".fnameescape(a:filePath)
		exe exprStr
		"expression found
		"get line numbers from quickfix
		for qfLine in getqflist()
			"call add(lineNums, qfLine.lnum)
			call add(lines, qfLine.text)
		endfor	
		if len(getqflist()) < 1
			"if we are here and getqflist() == []
			"then we hit a bug and vimgrep failed to populate getqflist
			"use alternative (slow) 'grep'
			let lines = s:grepFileSlow(a:filePath, a:expr)
		endif
		
	"catch  /^Vim\%((\a\+)\)\=:E480/
	catch  /.*/
		"echomsg "apexUtil#grepFile: expression NOT found: ". exprStr
	endtry
	
	" restore quickfix
	if a:0 < 1 || a:1 !~# 'Q'
		call setqflist(currentQuickFix)
	endif
	
	return lines
endfunction

" this is a very slow alternative to apexUtil#grepFile(file, expr)
function s:grepFileSlow(filePath, expr)
	let lines = []
	for line in readfile(a:filePath)
		if line =~ a:expr
			call add(lines, line)
		endif
	endfor
	return lines
endfunction


function! apexUtil#unescapeFileName(fileName)
	return substitute(a:fileName, '\\\(\\\|[^\\]\)', '\1', 'g')
endfunction

" command line parameter completion
" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
" candidates list of completion candidate values, e.g. ['val1', 'anotherVal']
"
function! apexUtil#commandLineComplete(arg, line, pos, candidates)
	let res = []
	for val in a:candidates
		if 0 == len(a:arg) || match(val, a:arg) >= 0 
			call add(res, val)
		endif	
	endfor	
	return res
endfunction	

function! apexUtil#getOrElse(var, defaultValue)
    if exists(a:var)
		let value = eval(a:var)
		if type(value) != type(a:defaultValue)
			call apexUtil#error("invalid type of variable " . a:var . ", valid value example: " . a:defaultValue)
		else
			return value
		endif
	endif
	return a:defaultValue
endfunction
