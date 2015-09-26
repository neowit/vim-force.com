" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexStage.vim
" Last Modified: 2012-10-14
" Author: Andrey Gavrikov 
" Version: 0.1
" Maintainers: 
"
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

let s:commentedLine = '#'
let s:header = [
			\ "# vim-force.com plugin - managing staged files",
			\ "# ..........................................................................",
			\ "# Review staged files and run :Write when done" ,
            \ "# You can comment out lines by putting hash # in front of the line",
			\ "# =========================================================================="
			\ ]
let s:headerLineCount = len(s:header)  

function! apexStage#open(filePath)

	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectName = projectPair.name
	let projectPath = projectPair.path

	" check if buffer with file types already exist
	if exists("g:APEX_STAGE_BUF_NUM") && bufloaded(g:APEX_STAGE_BUF_NUM)
		execute 'b '.g:APEX_STAGE_BUF_NUM
	else "load types list and create new buffer

		let stageFilePath = apexStage#getStageFilePath(projectPath)
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
		let g:APEX_STAGE_BUF_NUM = bufnr("%")

		call s:load() " load buffer content

		" Set the buffer name if not already set
		if bufname('%') != s:BUFFER_NAME
			exec 'file ' . fnameescape(s:BUFFER_NAME)
		endif

		"define commands for current buffer
		exec 'command! -buffer -bang -nargs=0 Write :call <SNR>'.s:sid.'_Write()'

		" write stage into a file every time before user leaving for another buffer 
		autocmd BufLeave <buffer> call apexStage#write()
		" reload stage from disk every time when entering buffer
		autocmd BufEnter <buffer> call s:load()
	endif

	" syntax highlight
	if has("syntax")
		syntax on
		exec "syn match ApexStageCommentedLine '^\s*".s:commentedLine.".*$'"
	endif

	exec "highlight link ApexStageCommentedLine Comment"
endfunction	

function! s:SID()
  " Return the SID number for current file
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfun
let s:sid = s:SID()

"write changes to stage cache file and delete Stage buffer
function! <SID>Write()
	call apexStage#write()
	:bd

endfunction

"write changes to stage cache file
function! apexStage#write()
	"check if there is anything to write
	if exists("g:APEX_STAGE_BUF_NUM") && bufloaded(g:APEX_STAGE_BUF_NUM) && exists("b:PROJECT_PATH")
		let lines = getbufline(g:APEX_STAGE_BUF_NUM, s:headerLineCount +1, line("$"))
		let stageFilePath = apexStage#getStageFilePath(b:PROJECT_PATH)

		call writefile(lines, stageFilePath)
		call apexUtil#info('Stage written to disk')
	endif
endfunction


function! apexStage#getStageFilePath(projectPath)
	return apexOs#joinPath([apex#getCacheFolderPath(a:projectPath), s:STAGE_FILE])
endfunction

" local getStageFilePath, when project path is already known
function s:getStageFilePath() 
	return apexStage#getStageFilePath(b:PROJECT_PATH)
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
            " remove commented out lines
            if line  !~ "^\\W*#"
                call add(lines, line)
            endif
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
		"file path in stage always uses / as path separator
		"let relPath = apexOs#joinPath([folder, fName])
		let relPath = apexOs#removeTrailingPathSeparator(folder) . "/" . fName
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

" add all open files to stage
function! apexStage#addOpen()
	let filePath = expand("%:p")
	let projectPath = apex#getSFDCProjectPathAndName(filePath).path
	let bufferList = apex#getOpenBuffers(projectPath, 'deployableOnly')
	for n in bufferList
		let fullpath = expand('#'.n.':p')
		call apexStage#add(fullpath)
	endfor
endfunction
"remove given file from stage cache
function! apexStage#remove(filePath)

	let projectPath = apex#getSFDCProjectPathAndName(a:filePath).path
	let stageFilePath = apexStage#getStageFilePath(projectPath)
	let filePair = apexOs#splitPath(a:filePath)
	let fName = filePair.tail
	let folder = apexOs#splitPath(filePair.head).tail
	"let relPath = apexOs#joinPath([folder, fName])
	let relPath = apexOs#removeTrailingPathSeparator(folder) . "/" . fName
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

" delete Stage buffer if loaded and clear global variable
function! apexStage#kill()
	if exists("g:APEX_STAGE_BUF_NUM")
		if bufloaded(g:APEX_STAGE_BUF_NUM)
			execute ":bd ".g:APEX_STAGE_BUF_NUM
		endif	
		unlet g:APEX_STAGE_BUF_NUM
	endif
endfunction	

" Clear Stage buffer from user added content
function! s:clear()
	" clear buffer first
	if exists("g:APEX_STAGE_BUF_NUM") && bufloaded(g:APEX_STAGE_BUF_NUM)
		let currBuff=bufnr("%")
		if currBuff != g:APEX_STAGE_BUF_NUM
			execute 'buffer ' . g:APEX_STAGE_BUF_NUM
		endif
		let lines = getbufline(g:APEX_STAGE_BUF_NUM, s:headerLineCount +1, line("$"))
		let firstLine = s:headerLineCount +1
		exe firstLine.',$delete'
		" delete stage buffer
		execute 'bd ' . g:APEX_STAGE_BUF_NUM 

		"switch back to current buffer
		if currBuff != g:APEX_STAGE_BUF_NUM
			execute 'buffer ' . currBuff
		endif
	endif

endfunction

" clear Stage buffer and disk file
function! apexStage#clear(filePath)

	"clear Stage buffer
	call s:clear()

	" clear file on disk
	let projectPath = apex#getSFDCProjectPathAndName(a:filePath).path
	let stageFilePath = apexStage#getStageFilePath(projectPath)

	if filereadable(stageFilePath)
		if 0 == delete(stageFilePath)
			call apexStage#kill()
			echo "Cleared stage from disk"
		else
			call apexUtil#warning('failed to delete stage file '.stageFilePath)
		end	
	else
		"just blank line to clear status line
		echo ""
	endif

endfunction	


" initialise stage header and load stage file
function! s:load()
	let stageFilePath = s:getStageFilePath()
	if !filereadable(stageFilePath) || len(readfile(stageFilePath, '', 1)) < 1
		"file does not exist or empty
		call apexUtil#warning("Nothing staged. use :ApexStageAdd to add files(s) first")
		return
	endif

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
endfunction
