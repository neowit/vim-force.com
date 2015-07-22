" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexCoverage.vim
" Last Modified: 2014-02-01
" Author: Andrey Gavrikov 
" Maintainers: 
"
" Apex code Coverage display functionality
"
"
if exists("g:loaded_apexCoverage") || &compatible
  finish
endif
let g:loaded_apexCoverage = 1

let s:display_state_by_file = {}

function apexCoverage#quickFixOpen(...) abort
	let filePath = expand("%:p")
	if a:0 > 0
		let filePath = a:1
	endif
	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	let projectPath = projectPair.path

	let coverageReportFile = apexTooling#getLastCoverageReportFile()
	if filereadable(coverageReportFile)
		let l:coverageList = []
		for jsonLine in readfile(coverageReportFile)
			let coverage = eval(jsonLine)
			let line = {}
			let linesTotalNum = coverage["linesTotalNum"]
			let linesNotCoveredNum = coverage["linesNotCoveredNum"]
			let linesCoveredNum = (linesTotalNum - linesNotCoveredNum)
			let percent = linesTotalNum > 0 ? linesCoveredNum * 100 / linesTotalNum : 0
			let fullPathName = apexOs#joinPath(projectPath, coverage["path"])

			let line.filename = fullPathName
			let line.text = "Total lines: " . linesTotalNum . "; Not Covered: " . linesNotCoveredNum . "; Covered: " . linesCoveredNum . "; " . percent . "%" 
			call add(l:coverageList, line)
			" call apexCoverage#hide(fullPathName)
			" call apexCoverage#toggle(fullPathName)

		endfor
        " sort by file name
        call sort(l:coverageList, "s:fileNameComparator")
        
		call setqflist(l:coverageList)
		if len(l:coverageList) > 0
			copen
		endif
	endif
	
endfunction

function! apexCoverage#toggle(filePath)
	let isDisplayed = has_key(s:display_state_by_file, a:filePath) &&  s:display_state_by_file[a:filePath]
	if isDisplayed
		" hide coverage signs
		call s:clearSigns(a:filePath)
		let s:display_state_by_file[a:filePath] = 0
	else
		" show coverage signs
		call s:showSigns(a:filePath)
	endif
endfunction

"Args:
"Param: buffer - number or name of buffer
function! apexCoverage#show(buffer)
	let l:buffer = -1
	
	if a:buffer == ''
		" No buffer provided, use the current buffer.
		let l:buffer = bufnr('%')
	elseif (a:buffer + 0) > 0
		" A buffer number was provided.
		let l:buffer = bufnr(a:buffer + 0)
	else
		" A buffer name was provided.
		let l:buffer = bufnr(a:buffer)
		if l:buffer < 0
			" try as class
			let l:buffer = bufnr(a:buffer . ".cls")
		endif
		if l:buffer < 0
			" try as trigger
			let l:buffer = bufnr(a:buffer . ".trigger")
		endif
	endif
	
	if l:buffer < 0
		call apexUtil#error("No matching buffer for '" . a:buffer . "' Make sure that the target file is aclually open in one of vim buffers.")
		return
	endif
	
	let filePath = expand('#'.l:buffer.':p')

	" check if proivided file is a valid one (i.e. class or trigger)
	if filePath !~ '\.cls$\|\.trigger$'
		call apexUtil#error("File " . filePath . " is not valid for coverage display")
		return
	endif
	let s:display_state_by_file[filePath] = 0
	call apexCoverage#toggle(filePath)
	
	" switch to this buffer
	exe "buffer ".l:buffer  
endfunction
"Param1: (optional) file path where signs must be cleared
"					if not provided then clear signs in all files
function! apexCoverage#hide(...)
	if a:0 > 0
		let filePath = a:1
		let s:display_state_by_file[filePath] = 1
		call apexCoverage#toggle(filePath)
	else
		" hide in all files
		call s:clearSigns()
	endif
endfunction

"Args:
"Param1: (optional) file path where signs must be cleared
"					if not provided then clear signs in all files
function! s:clearSigns(...) abort
	if a:0 > 0
		try
			exe ":sign unplace * file=" . a:1
		catch /^Vim\%((\a\+)\)\=:E474/
			if !has('signs')
				let msg = "Your version of Vim does not support ':sign unplace * file=filename' version of :sign command. "
				let msg .= "You may want to re-compile vim with '--with-features=huge' or upgrade to a newer Vim version"
				call apexUtil#warning( msg )
			else
				call apexUtil#warning( v:exception )
			endif 
		endtry
	else
		exe ":sign unplace *"
	endif
endfunction

function! s:defineHighlight()
    hi SignColumn guifg=#004400 guibg=green ctermfg=40 ctermbg=40
    hi uncovered guifg=#ff2222 guibg=red ctermfg=1 ctermbg=1
    sign define uncovered text=00 texthl=uncovered
endfunction

"Returns: dictionary which looks like so:
"{'path' : 'src/classes/AccountController.cls', 
" 'linesTotalNum': 40, 'linesNotCoveredNum': 16,
" 'linesNotCovered" : [8, 9, 11,12, 20, 21, 24, 25, 27, 28, 31, 32, 34, 35, 37, 38]
"}
function! s:loadCoverageData(filePath)
	let resultMap = {}
	let fileName = apexOs#splitPath(a:filePath).tail
	let coverageReportFile = apexTooling#getLastCoverageReportFile()
	"TODO remove line below and uncomment one above
	"let coverageReportFile = '/private/var/folders/j7/j2yjllg10wz5__x5f8h2w10c0000gn/T/coverage7187158401431933096.txt'
	if filereadable(coverageReportFile) 
		let jsonLines = apexUtil#grepFile(coverageReportFile, fileName)
		if len(jsonLines) > 0
			let resultMap = eval(jsonLines[0])
		endif
	endif
	return resultMap
endfunction

function! s:showSigns(filePath) abort
    call s:defineHighlight()
    call s:clearSigns(a:filePath)

	let filePath = a:filePath

	let coverageData = s:loadCoverageData(filePath)
	"echo "coverageData=" . string(coverageData)
	if len(coverageData) > 0
		let linesNotCovered = coverageData.linesNotCovered
		if len(linesNotCovered) < 1
			" without next line, line after it does not appear, not sure why
			echo ' ' 
			call apexUtil#info('No uncovered lines')
		else
			let index = 1
			for lineNum in linesNotCovered
				execute ":sign place ". index ." line=". lineNum ." name=uncovered file=".filePath
				let index += 1
			endfor
			let s:display_state_by_file[filePath] = 1
		endif
	else
		echo "\n"
		call apexUtil#warning("No coverage data for " . apexOs#splitPath(filePath).tail)
		let s:display_state_by_file[filePath] = 0
	endif
endfunction

" helper to sort list of coverage data objects in file name order
function! s:fileNameComparator(jsonLeft, jsonRight)
    let l:leftFilename = a:jsonLeft.filename
    let l:rightFilename = a:jsonRight.filename
    return l:leftFilename == l:rightFilename ? 0 : l:leftFilename >l:rightFilename ? 1 : -1 
endfunction

" map user defined key to open file under cursor and toggle Test Coverage signs if current file is apex file
if exists("g:apex_quickfix_coverage_toggle_shortcut")
    exe "autocmd! BufReadPost quickfix nmap <buffer> " . g:apex_quickfix_coverage_toggle_shortcut." <CR>:call <SID>quickfixActionOverride()<CR>"
endif

function! s:quickfixActionOverride()
    if &ft == "apexcode"
        call apexCoverage#toggle(expand("%:p"))
    endif
endfunction
