" File: apexCoverage.vim
" Author: Andrey Gavrikov 
" Version: 1.0
" Last Modified: 2014-02-01
" Copyright: Copyright (C) 2010-2014 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" Apex code Coverage display functionality
" Part of vim/force.com plugin
"
"
if exists("g:loaded_apexCoverage") || &compatible
  finish
endif
let g:loaded_apexCoverage = 1

let s:display_state_by_file = {}
function! apexCoverage#toggle(filePath)
	let isDisplayed = has_key(s:display_state_by_file, a:filePath) &&  s:display_state_by_file[a:filePath]
	if isDisplayed
		" hide coverage signs
		call s:clearSigns(a:filePath)
		let s:display_state_by_file[a:filePath] = 0
	else
		" show coverage signs
		call s:showSigns(a:filePath)
		let s:display_state_by_file[a:filePath] = 1
	endif
endfunction

"Param1: (optional) file path where signs must be cleared
"					if not provided then clear signs in all files
function! apexCoverage#hide(...)
	if a:0 > 0
		let filePath = a:1
		let s:display_state_by_file[a:filePath] = 1
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
		exe ":sign unplace * file=" . a:1
	else
		exe ":sign unplace *"
	endif
endfunction

function! s:defineHighlight()
    hi SignColumn guifg=#004400 guibg=green ctermfg=40 ctermbg=40
    hi uncovered guifg=#ff2222 guibg=red ctermfg=1 ctermbg=1
    hi covered guifg=#004400 guibg=green ctermfg=40 ctermbg=40
    sign define uncovered text=00 texthl=uncovered
    sign define covered text=XX texthl=covered
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
		let index = 1
		for lineNum in linesNotCovered
			execute ":sign place ". index ." line=". lineNum ." name=uncovered file=".filePath
			let index += 1
		endfor
		let s:display_state_by_file[filePath] = 1
	else
		call apexUtil#warning("No coverage data for " . apexOs#splitPath(filePath).tail)
	endif
endfunction

