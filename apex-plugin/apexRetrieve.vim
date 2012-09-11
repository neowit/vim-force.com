" File: apexRetrieve.vim
" Author: Andrey Gavrikov 
" Version: 0.1
" Last Modified: 2012-09-07
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" apexRetrieve.vim - part of vim-force.com plugin
" Selective Metadata retrieval methods

if exists("g:loaded_apex_retrieve") || &compatible || stridx(&cpo, "<") >=0
	"<SID> requires that the '<' flag is not present in 'cpoptions'.
	finish
endif
"let g:loaded_apex_retrieve = 1

let s:header = [
  \ " || vim-force.com plugin",
  \ " || mark/select types to retrieve, then give command :ApexRetrieve" ,
  \ " || t=toggle Select/Deselect, e=expand current",
  \ " || :Expand = expand all selected",
  \ " || :Retrieve = retrieve selected types into the project folder",
  \ " ============================================================================="
  \ ]
let s:headerLineCount = len(s:header)  

let s:MARK_SELECTED = "*"
let s:HIERARCHY_SHIFT = "--"

let s:ALL_METADATA_LIST_FILE = "all-meta-types.txt"
let s:CACHE_FOLDER_NAME = ".vim-force.com"

let b:PROJECT_NAME = ""
let b:PROJECT_PATH = ""
" loaded s:CACHED_META_TYPES looks like this:
"	{CustomObject: {XMLName:'CustomObject', DirName:'Objects', Suffix:'object', HasMetaFile:'false', InFolder:'false', ChildObjects:[CustomField, BusinessProcess,...]}}
let s:CACHED_META_TYPES = {} 


" return existing or create new and return path to
" plugin cache directory
function! s:getCacheFolderPath(projectPath)
	let metaTypesFolderPath = apexOs#joinPath([a:projectPath, s:CACHE_FOLDER_NAME])

	if !isdirectory(metaTypesFolderPath)
		"cache directory does not exist, need to create it first
		call apexOs#createDir(metaTypesFolderPath)
	endif
	return metaTypesFolderPath
endfunction

function! apexRetrieve#getCachedMetMap()
	if len(s:CACHED_META_TYPES) < 1
		" need to initialise the map
	
	endif
	return s:CACHED_META_TYPES
endfunction

function! s:getMetaTypesCache(allMetaTypesFilePath)
	let allMetaTypesFilePath = a:allMetaTypesFilePath

	"echo "allMetaTypesFilePath=".allMetaTypesFilePath
	
	" parse loaded file and extract all meta types
	" single type in the file returned by describeMetadata ant task looks
	" like this
	" ************************************************************
	" XMLName: CustomObject
	" DirName: objects
	" Suffix: object
	" HasMetaFile: false
	" InFolder: false
	" ChildObjects:
	" CustomField,BusinessProcess,RecordType,WebLink,ValidationRule,NamedFilter,SharingReason,ListView,FieldSet,ApexTriggerCoupling,************************************************************
	" ************************************************************
	
	" we need to parse the file and cache results
	"
	let currentTypeName = ""
	let simpleKeys = ["DirName", "Suffix", "HasMetaFile", "InFolder"]
	for line in readfile(allMetaTypesFilePath, '', 10000) " assuming metadata types file will never contain more than 10K lines
		"echo "line=".line
		let items = split(line, ':')
		if len(items) < 2
			continue
		endif

		let key = apexUtil#trim(items[0])
		let value = apexUtil#trim(items[1])
		
		if "XMLName" == key
			" initialise new type
			let currentTypeName = value
			let currentElement = {}
			let currentElement[currentTypeName] = {}
			call extend(s:CACHED_META_TYPES, currentElement)
		elseif index(simpleKeys, key) >=0
			let currentElement = s:CACHED_META_TYPES[currentTypeName]
			let currentElement[key] = value
			"let s:CACHED_META_TYPES[currentTypeName] = currentElement
		elseif "ChildObjects" == key
			let currentElement = s:CACHED_META_TYPES[currentTypeName]
			let children = []
			" value of this item is represented as a comma separated line
			" which ends with '****...' or ',null,***...'
			for objName in split(value,',')
				"echo "objName=".objName
				if match(objName, '*') < 0 && match(objName, 'null') < 0
					"echo "add ". objName
					call add(children, objName)
				endif
			endfor	
			let currentElement[key] = children
			"let s:CACHED_META_TYPES[currentTypeName] = currentElement
		endif	
	endfor
	"now we have a map of all metadata types in s:CACHED_META_TYPES
	
	"echo "s:CACHED_META_TYPES=\n"
	"echo s:CACHED_META_TYPES

	return s:CACHED_META_TYPES

endfunction	

" return path to cached metadata file
" if file does not exist then plugin will attempt loading list
" of supported metadata types from SFDC
"
" return: list of all supported metadata types
function! s:getMetaTypesList(projectName, projectPath, forceLoad)
	let allMetaTypesFilePath = apexOs#joinPath([s:getCacheFolderPath(a:projectPath), s:ALL_METADATA_LIST_FILE])

	if !filereadable(allMetaTypesFilePath) || a:forceLoad
		"cache file does not exist, need to load it first
		let response = input('Load list of supported metadata types from server?: [y/n]? ')
		if 'y' != response && 'Y' != response
			" clear message line
			echo "\nCancelled" 
			return []
		endif

		call apexAnt#loadMetadataList(a:projectName, a:projectPath, allMetaTypesFilePath)
		

	endif

	let typesMap = s:getMetaTypesCache(allMetaTypesFilePath)
	" dump types in user friendly format
	if len(typesMap) < 1
		echoerr "Failed to load list of supported metadata types"
		return []
	endif
	let types = keys(typesMap)
	let types = sort(types)
	"call writefile(types, metaTypesFilePath)
	return types
endfunction

" open existing or load new file with metadata types
" retrieved list of supported metadata types is stored
" in ./vim-force.com folder under project root, next to ./src/
function! apexRetrieve#open(projectName, projectPath)

	" check if buffer with file types already exist
	if exists("g:APEX_META_TYPES_BUF_NUM") && bufloaded(g:APEX_META_TYPES_BUF_NUM)
		execute 'b '.g:APEX_META_TYPES_BUF_NUM
	else "load types list and create new buffer
		let metaTypes = s:getMetaTypesList(a:projectName, a:projectPath, 0)
		if len(metaTypes) < 1
			"file does not exist, and load was abandoned
			return ""
		endif

		new
		setlocal buftype=nofile
		setlocal bufhidden=hide " when user switches to another buffer, just hide meta buffer but do not delete
		setlocal nowrite
		setlocal modifiable
		setlocal noswapfile

		"initialise variables
		let b:PROJECT_NAME = a:projectName
		let b:PROJECT_PATH = a:projectPath
		let g:APEX_META_TYPES_BUF_NUM = bufnr("%")

		" load header and types list
		let i = 0
		while i < s:headerLineCount
			call setline(i+1, s:header[i])
			let i += 1
		endwhile

		for type in metaTypes
			call setline(i+1, type)
			let i += 1
		endfor

		" Define key mapping for current buffer
		exec 'nnoremap <buffer> <silent> t :call <SNR>'.s:sid.'_ToggleSelected()<CR>'
		exec 'nnoremap <buffer> <silent> e :call <SNR>'.s:sid.'_ExpandCurrent()<CR>'
		" Define commands for current buffer
		exec 'command! -buffer -bang -nargs=0 Expand :call <SNR>'.s:sid.'_ExpandSelected()'
		exec 'command! -buffer -bang -nargs=0 Retrieve :call <SNR>'.s:sid.'_RetrieveSelected()'

	endif

endfunction

" mark entry as Selected/Deselected
function! <SID>ToggleSelected()
  " Toggle type selection
	" let lineNum = line('.')
	" let lineStr = getline(lineNum)
	let lineStr = s:getCurrentLine()
	if s:isSelected(lineStr)
		"remove mark
		let lineStr = substitute(lineStr, s:MARK_SELECTED, "", "")
	else
		"add mark
		let lineStr = s:MARK_SELECTED . lineStr
	endif
	call s:setCurrentLine(lineStr)
endfunction

" retrieve children of selected component
" get detail information about metadata components of selected type
function! <SID>ExpandCurrent()
	echo "load children of current line"

	let lineNum = line('.')
	let lineStr = s:getCurrentLine()
	"remove mark if exist
	let lineStr = substitute(lineStr, s:MARK_SELECTED, "", "")
	let typeName = apexUtil#trim(lineStr)

	" load children of given metadata type
	let tmpfile = tempname()
	call apexAnt#listMetadata(b:PROJECT_NAME, b:PROJECT_PATH, tmpfile, lineStr)
	if !filereadable(tmpfile)
		call apexUtil#warning( "No subtypes of ".lineStr." found.")
		return
	endif	
	" parse returned file into manageable format
	let typesMap = s:parseListMetadataResult(typeName, tmpfile)
	if len(typesMap) > 0
		let typesList = sort(keys(typesMap))
		let shiftedList = []
		" append types below current
		for curType in typesList
			call add(shiftedList, s:HIERARCHY_SHIFT . curType)
		endfor
		call append(lineNum, shiftedList)
	endif
endfunction

function! <SID>ExpandSelected()
	echo "Expand children of all selected items"
	let lines = getline(1, line("$"))
	let selectedLines = []
	"let l:count = 0

	for line in lines
		"echo "line=".line
		if s:isSelected(line)
			let line = substitute(line, s:MARK_SELECTED, "", "")
			echo "selected line=".line
			let selectedLines = add(selectedLines, line)
		endif
		"let l:count = l:count +1
	endfor
	if len(selectedLines) >0
		"insert child types of selected lines into buffer
	endif
endfunction

function! <SID>RetrieveSelected()
	echo "Retrieve all selected items"
endfunction

function! s:isSelected(lineStr)
	let markIndex = stridx(a:lineStr, s:MARK_SELECTED)
	return markIndex >= 0
endfunction

function! s:getCurrentLine()
	let lineNum = line('.')
	let lineStr = getline(lineNum)
	return lineStr
endfunction

function! s:setCurrentLine(line)
	let lineNum = line('.')
	let lineStr = setline(lineNum, a:line)
endfunction

function! s:SID()
  " Return the SID number for a file
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfun
let s:sid = s:SID()

"
"return: map of types which looks like this
" assuming metadataType = CustomObject
" {
" 'Activity': {FileName: 'objects/Activity.object', 'Manageable State': 'null'},
" 'Group_subsidiary__c': {FileName: ' objects/Group_subsidiary__c.object', 'Manageable State': 'unmanaged'},
" ...
" }
"
function! s:parseListMetadataResult(metadataType, fname)
	let l:metaMap = {}
	let typeDef = s:CACHED_META_TYPES[a:metadataType]
	if len(typeDef) < 1
		echoerr "list of supported metadata types has not been loaded."
		return {}
	endif

	let dirName = typeDef["DirName"]
	let suffix = typeDef["Suffix"]

	"result of 'listMetadata' looks like this
	"
	"************************************************************
	"FileName: objects/Activity.object
	"FullName/Id: Activity/
	"Manageable State: null
	"Namespace Prefix: 
	"Created By (Name/Id): Andrey Gavrikov/00530000000dUMVAA2
	"Last Modified By (Name/Id): Andrey Gavrikov/00530000000dUMVAA2
	"************************************************************
	"************************************************************
	"FileName: objects/Group_subsidiary__c.object
	"FullName/Id: Group_subsidiary__c/01I600000005JyoEAE
	"Manageable State: unmanaged
	"Namespace Prefix: null
	"Created By (Name/Id): Andrey Gavrikov/00530000000dUMVAA2
	"Last Modified By (Name/Id): Andrey Gavrikov/00530000000dUMVAA2
	"************************************************************
	
	for line in readfile(a:fname, '', 10000) " assuming metadata types file will never contain more than 10K lines
		"echo "line=".line
		let items = split(line, ':')
		if len(items) < 2
			continue
		endif

		let key = apexUtil#trim(items[0])
		let value = apexUtil#trim(items[1])

		if "FileName" == key
			" initialise new type
			" remove dir name
			let name = substitute(value, "^".dirName."/", "", "") " start from the beginning
			" remove file extension name
			let name = substitute(name, ".".suffix."$", "", "") " substitute only tail
			let currentTypeName = name
			let currentElement = {}
			let l:metaMap[currentTypeName] = currentElement
			let currentElement[key] = value
			"call extend(currentElement, {key:value})
		elseif len(value) > 0
			let currentElement = l:metaMap[currentTypeName]
			let currentElement[key] = value
		endif	
	endfor

	"echo "l:metaMap=\n"
	"echo l:metaMap
	return l:metaMap
endfunction

"function! TestParseListMetadataResult(metadataType, fname)
"	call s:parseListMetadataResult(a:metadataType, a:fname)
"endfunction

function! TestRetrieve()

	"call <SID>ToggleSelected()
	"call <SID>ExpandCurrent()
	"call <SID>RetrieveSelected()
endfunction
