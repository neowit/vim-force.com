" File: apexStage.vim
" Author: Andrey Gavrikov 
" Version: 0.1
" Last Modified: 2012-10-14
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" apexStage.vim - part of vim-force.com plugin
" Staging files for further operations like Delete or Deploy

if exists("g:loaded_apex_stage") || &compatible || stridx(&cpo, "<") >=0
	"<SID> requires that the '<' flag is not present in 'cpoptions'.
	finish
endif

let g:loaded_apex_stage = 1

let s:STAGE_FILE = "stage-list.txt"
let b:PROJECT_NAME = ""
let b:PROJECT_PATH = ""
let s:BUFFER_NAME = 'vim-force.com Staged Files'

let s:instructionPrefix = '||'
let s:instructionFooter = '='
let s:header = [
			\ "|| vim-force.com plugin - managing staged files",
			\ "||",
			\ "|| review staged files and run :Write when done" ,
			\ "============================================================================="
			\ ]
let s:headerLineCount = len(s:header)  

function! apexStage#open(filePath)

	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectName = projectPair.name
	let projectPath = projectPair.path
	"init header and length variables
	call s:init(projectPath)

	" check if buffer with file types already exist
	if exists("g:APEX_META_TYPES_BUF_NUM") && bufloaded(g:APEX_META_TYPES_BUF_NUM)
		execute 'b '.g:APEX_META_TYPES_BUF_NUM
	else "load types list and create new buffer
		let stageFilePath = apexOs#joinPath([apex#getCacheFolderPath(projectPath), s:STAGE_FILE])
		if !filereadable(stageFilePath) || len(readfile(stageFilePath, '', 1)) < 1
			"file does not exist, and load was abandoned
			call apexUtil#warning("Nothing staged. use :ApexStageAdd to add files(s) first")
			return
		endif

		enew
		
		setlocal buftype=nofile
		setlocal bufhidden=hide " when user switches to another buffer, just hide meta buffer but do not delete
		setlocal modifiable
		setlocal noswapfile
		setlocal nobuflisted

		"initialise variables
		let b:PROJECT_NAME = projectName
		let b:PROJECT_PATH = projectPath
		let b:SRC_PATH = apex#getApexProjectSrcPath(a:filePath)
		let g:APEX_META_TYPES_BUF_NUM = bufnr("%")

		" load header and types list
		let i = 0
		while i < s:headerLineCount
			call setline(i+1, s:header[i])
			let i += 1
		endwhile


		for line in readfile(stageFilePath, '', 10000) " assuming stage file will never contain more than 10K lines
			call setline(i+1, line)
			let i += 1
		endfor

		" Set the buffer name if not already set
		if bufname('%') != s:BUFFER_NAME
			exec 'file ' . fnameescape(s:BUFFER_NAME)
		endif

		"define commands for current buffer
		exec 'command! -buffer -bang -nargs=0 Write :call <SNR>'.s:sid.'_Write()'

	endif

	" syntax highlight
	if has("syntax")
		syntax on
		exec "syn match ApexStageInstructionsText '^\s*".s:instructionPrefix.".*'"
		exec "syn match ApexStageInstructionsFooter '^\s*".s:instructionFooter."*$'"
		"exec 'syn match ApexStageModifiedItem /'.s:SELECTED_LINE_REGEX.'/'
	endif

	exec "highlight link ApexStageInstructionsText Constant"
	exec "highlight link ApexStageInstructionsFooter Comment"
	"exec "highlight link ApexStageModifiedItem Keyword"
endfunction	

function! s:SID()
  " Return the SID number for current file
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfun
let s:sid = s:SID()

"write changes to stage cache file
function! <SID>Write()
	let lines = getline(s:headerLineCount +1, line("$"))
	let stageFilePath = apexStage#getStageFilePath(b:PROJECT_PATH)

	call writefile(lines, stageFilePath)
	:bd

endfunction
function! apexStage#getStageFilePath(projectPath)
	return apexOs#joinPath([apex#getCacheFolderPath(a:projectPath), s:STAGE_FILE])
endfunction

" list staged files
"Args:
"projectPath - path to current project 
"Return:
" list of staged files
" e.g.
" [classes/MyClass.cls,  pages/MyPage.page, ...]
function! apexStage#list(projectPath)
	"check that file is not already staged
	let lines = []
	let alreadyAdded = 0

	let stageFilePath = apexStage#getStageFilePath(a:projectPath)
	if filereadable(stageFilePath)
		for line in readfile(stageFilePath, '', 10000) " assuming stage file will never contain more than 10K lines
			call add(lines, line)
		endfor
	endif
	return lines

endfunction
" stage file for further operation like Deploy or Delete
"Args:
"param 1: [optional] path to file which will be staged
function! apexStage#add(...)
	let filePath = expand("%:p")
	if a:0 > 0
		let filePath = a:1
	endif

	let projectPath = apex#getSFDCProjectPathAndName(filePath).path
	if  len(projectPath) > 0
		let stageFilePath = apexStage#getStageFilePath(projectPath)
		let filePair = apexOs#splitPath(filePath)
		let fName = filePair.tail
		let folder = apexOs#splitPath(filePair.head).tail
		let relPath = apexOs#joinPath([folder, fName])
		"check that file is not already staged
		let lines = []
		let alreadyAdded = 0

		if filereadable(stageFilePath)
			for line in readfile(stageFilePath, '', 10000) " assuming stage file will never contain more than 10K lines
				call add(lines, line)
				if line =~? "^".relPath."$"
					let alreadyAdded = 1
				endif	
			endfor
		endif
		if alreadyAdded > 0
			call apexUtil#warning('File "'.relPath.'" already staged. SKIP ')
			return
		endif
		call add(lines, relPath)
		call writefile(lines, stageFilePath)
		echo "staged ".relPath
	endif

endfunction	

"remove given file from stage cache
function! apexStage#remove(filePath)

	let projectPath = apex#getSFDCProjectPathAndName(a:filePath).path
	let stageFilePath = apexStage#getStageFilePath(projectPath)
	let filePair = apexOs#splitPath(a:filePath)
	let fName = filePair.tail
	let folder = apexOs#splitPath(filePair.head).tail
	let relPath = apexOs#joinPath([folder, fName])
	"check that file is not already staged
	let lines = []
	let found = 0

	if filereadable(stageFilePath)
		for line in readfile(stageFilePath, '', 10000) " assuming stage file will never contain more than 10K lines
			if line =~? "^".relPath."$"
				let found = 1
			else	
				call add(lines, line)
			endif	
		endfor
	endif
	if found > 0
		call writefile(lines, stageFilePath)
		echo "unstaged ".relPath
	else
		echo "not staged"
	endif

endfunction	

function! apexStage#clear(filePath)

	let projectPath = apex#getSFDCProjectPathAndName(a:filePath).path
	let stageFilePath = apexStage#getStageFilePath(projectPath)

	if filereadable(stageFilePath)
		if 0 == delete(stageFilePath)
			echo "cleared stage"
		else
			call apexUtil#warning('failed to delete stage file '.stageFilePath)
		end	
	else
		"just blank like to clear status line
		echo ""
	endif

endfunction	


" call this method before any other as soon as Project Path becomes available
function! s:init(projectPath)
endfunction
