" File: apexOs.vim
" Author: Andrey Gavrikov 
" Version: 1.0
" Last Modified: 2012-03-05
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
" OS specific methods
" Part of vim/force.com plugin
"
"
if exists("g:loaded_apexOs") || &compatible
  finish
endif
let g:loaded_apexOs = 1

" check that required global variables are defined
let s:requiredVariables = ["g:apex_backup_folder", "g:apex_temp_folder", "g:apex_deployment_error_log", "g:apex_properties_folder"]
for varName in s:requiredVariables
	if !exists(varName)
		echoerr "Please define ".varName." See :help force.com-settings"
	endif
endfor	

let s:is_windows = has("win32") || has("win64")

"Function: s:let() function {{{2
" initialise given variable if it is not already set
"
"Args:
"var: the name of the variable to be initialised
"value: the value to initialise to
"
"Returns: 1 if the variable is set inside this method, otherwise 0
function! s:let(var, value)
    if !exists(a:var)
        exec 'let ' . a:var . ' = ' . "'" . substitute(a:value, "'", "''", "g") . "'"
        return 1
    endif
    return 0
endfunction

"Function: s:trim() function {{{1
" trim spaces at the end
"Args:
" str: input string
"Returns: trimmed string value or copy of existing string if nothing needed to
"be removed
function s:trim(str)
	return substitute(a:str,"^\\s\\+\\|\\s\\+$","","g") 
endfunction	

"""""""""""""""""""""""""""""""""""""""""""""""
" OS Dependent shell commands
"""""""""""""""""""""""""""""""""""""""""""""""
" space at the end of command is important
if s:is_windows
	call s:let('g:apex_binary_remove_dir', 'rmdir /s /q ')
	call s:let('g:apex_binary_copy_file', 'copy ')
	call s:let('g:apex_binary_touch', 'touch.exe ')
	call s:let('g:apex_binary_tee', 'tee.exe ')
else
	call s:let('g:apex_binary_create_dir', 'mkdir ')
	call s:let('g:apex_binary_remove_dir', 'rm -R ')
	call s:let('g:apex_binary_copy_file', 'cp ')
	call s:let('g:apex_binary_touch', 'touch ')
	call s:let('g:apex_binary_tee', 'tee ')
endif
" check if unix utils are executable
if !executable(s:trim(g:apex_binary_touch))
	echoerr g:apex_binary_touch." is not available or not executable. see :help force.com-unix_utils"
	finish
endif	
if !executable(s:trim(g:apex_binary_tee))
	echoerr g:apex_binary_tee." is not available or not executable. see :help force.com-unix_utils"
	finish
endif	

"set desired API version
call s:let('g:apex_API_version', '26.0')

" set pollWaitMillis for ant tasks. See ant-salesforce.jar
" documentation for 'pollWaitMillis' parameter
" the smaller the value defined by pollWaitMillis the quicker deploy will
" finish, but on slow connections larger values, like 10000 may be necessary
call s:let('g:apex_pollWaitMillis', '1000')


"""""""""""""""""""""""""""""""""""""""""""""""
" OS Dependent methods
"""""""""""""""""""""""""""""""""""""""""""""""
function! apexOs#browsedir(prompt, startDir)
	let fPath = getcwd()
	let prompt = 'Select Folder'
	if len(a:prompt) >0
		let prompt = a:prompt
	endif
	if len(a:startDir) >0
		let fPath = a:startDir
	endif
	if has("macunix")
		" in current version of MacVim buil-in function browsedir() produces
		" file selection dialogue instead of folder selection, so have to use osascript instead
		let strCommand ='osascript  -e "tell application \"Finder\"" -e "activate" -e "set fpath to POSIX path of (choose folder default location \"'.fPath.'\" with prompt \"'.prompt.'\")" -e "return fpath" -e "end tell"'
		let fPath=system(strCommand)
		"clean path from new line characters returned by osascript
		let fPath = substitute(fPath, "\n", "", "")
	else
		" standard built-in method
		let fPath = browsedir(prompt, fPath)
	endif	
	return fPath
endfunction	

function! apexOs#getTempFolder()
	return g:apex_temp_folder
endfunction	

function! apexOs#getBackupFolder()
	return g:apex_backup_folder
endfunction	

" OS dependent temporary directory create/delete
function! apexOs#createTempDir()
	let tempFolderPath = apexOs#getTempFolder()
	if has("unix")
		" remove existing folder
		silent exe "!rm -R ". shellescape(tempFolderPath)
	elseif s:is_windows
		silent exe "!rd ".GetWin32ShortName(tempFolderPath)." /s /q "
	else
		echoerr "Not implemented"
		return ""
	endif
	" recreate temp folder
	call apexOs#createDir(tempFolderPath)
	return tempFolderPath
	return tempFolderPath
endfunction
" 
" Os dependent directory create
function! apexOs#createDir(path)
	let path = apexOs#removeTrailingPathSeparator(a:path)
	if isdirectory(path)
		echoerr path." already exists, skip createDir()"
		return
	endif	
	if has("unix")
		call mkdir(path, "p", 0700)
	elseif s:is_windows
		call mkdir(path, "p")
	else
		echoerr "Not implemented"
	endif
endfunction

" standard shellescape() function does not escape all necessary characters,
" e.g. ( and ) so have to use custom function
" TODO - test on win32
function! apexOs#shellescape(val)
	let val = shellescape(a:val)
	if has("unix")
		 "return escape(val, '%()')
		 return escape(val, '%')
	elseif s:is_windows
		return GetWin32ShortName(a:fname)
	endif
	return val
endfunction
" 
" Os dependent file copy
function! apexOs#copyFile(srcPath, destPath)
	let sourcePath = apexOs#shellescape(a:srcPath)
	let destinationPath = apexOs#shellescape(a:destPath)
	if has("unix")
		"echo "cp " . sourcePath . " " . destinationPath
		silent exe "!cp " . sourcePath . " " . destinationPath
	elseif s:is_windows
		silent exe "!copy " . sourcePath . " " . destinationPath
	else
		echoerr "Not implemented"
	endif
endfunction

"OS dependent set file time
"Args:
" filePath: full file path
" time: result returned getftime({fname}), measured as seconds since 1st Jan 1970, 
function! apexOs#setftime(filePath, time)
	if has("unix")
		let stamp = strftime("%Y%m%d%H%M.%S", a:time)
		silent exe "!touch -t ".stamp." ".shellescape(a:filePath)
	elseif s:is_windows
		" win32 format is: MMDDhhmm[[CC]YY][.ss]
		let stamp = strftime("%m%d%H%M%Y.%S", a:time)
		silent exe "!".g:apex_binary_touch." -t ".stamp." ".shellescape(a:filePath)
	else
		echoerr "Not implemented"
	endif
endfun



" param: path to this (apex.vim) script
" return full path of the script to run for SFDC org refresh
"function! apexOs#getRefreshShellScriptPath(apexPluginFolderPath)
"	if has("unix")
"		return shellescape(apexUtil#joinPath([a:apexPluginFolderPath, "build.sh"]))
"	elseif s:is_windows 
"		return shellescape(apexUtil#joinPath([a:apexPluginFolderPath, "build.cmd"]))
"	else
"		echoerr "not implemented"
"	endif	
"endfun	

" param: path to this (apex.vim) script
" return full path of the script to run for SFDC org deploy
function! apexOs#getDeployShellScriptPath(apexPluginFolderPath)
	if has("unix")
		return shellescape(apexUtil#joinPath([a:apexPluginFolderPath, "build.sh"]))
	elseif s:is_windows
		return shellescape(apexUtil#joinPath([a:apexPluginFolderPath, "build.cmd"]))
	else
		echoerr "not implemented"
	endif	
endfun	

" remove trailing path separator
" i.e. make /path/to/folder from /path/to/folder/
function! apexOs#removeTrailingPathSeparator (path)
	return substitute (a:path, '[/\\]$', '', '')
endfun

" "foo/bar/buz/hoge" -> { head: "foo/bar/buz/", tail: "hoge" }
" taken from fuzzy finder plugin
function! apexOs#splitPath(path)
	let path = apexOs#removeTrailingPathSeparator(a:path)
	let head = matchstr(path, '^.*[/\\]')
	return  {
				\   'head' : head,
				\   'tail' : path[strlen(head):]
				\ }
endfunction

" \ on Windows unless shellslash is set, / everywhere else.
function! apexOs#getPathSeparator()
  return !exists("+shellslash") || &shellslash ? '/' : '\'
endfunction


" returns list of paths.
" An argument for glob() is normalized in order to avoid a bug on Windows.
" taken from fuzzy finder plugin
function! apexOs#glob(expr)
  " Substitutes "\", because on Windows, "**\" doesn't include ".\",
  " but "**/" include "./". I don't know why.
  return split(glob(substitute(a:expr, '\', '/', 'g')), "\n")
endfunction


" windows XP requires command which contains spaces to be enclosed in quotes
" twice, ex:
" ""d:\my path\build.cmd" "param 1" "param 2" param3"
"Args:
" param 1: command to execute
" param 2: [optional] string of options - 
"	b - command will be executed in background ignored on MS Windows
"	M - disable --more-- prompt when screen fills up with messages
function! apexOs#exe(...)
	let result = a:1
	let disableMore = 0
	if s:is_windows
		let result = '"'.result.'"'
	elseif a:0 > 1 
		if a:2 =~ "b"
			let result .= ' &'
		endif
		let disableMore = a:2 =~ "M"
	endif

	"temporarily disable more if enabled
	"also see :help hit-enter
	let reEnableMore = 0
	if disableMore
		let reEnableMore = &more
		set nomore
	endif

	exe "!".result

	if disableMore && reEnableMore
		set more
	endif
	"call system(result) " system() does not show any progress
endfunction	

" @return: true of given path name has trailing path separator
" ex: 
"	echo hasTrailingPathSeparator("/my/path") = 0
"	echo hasTrailingPathSeparator("/my/path/") = 1
function! apexOs#hasTrailingPathSeparator(filePath)
	if match(a:filePath, '.*[/\\]$') >= 0
		return 1
	endif	
	return 0
endfunction	

function! apexOs#joinPath(filePathList)
	let resPath = ''
	for path in a:filePathList
		if len(resPath)>0 
			if apexOs#hasTrailingPathSeparator(resPath)
				let resPath .= path
			else
				let resPath = join([resPath, path], apexOs#getPathSeparator())
			endif
		else
			let resPath = path
		endif	
	endfor
	return resPath
endfunction	

