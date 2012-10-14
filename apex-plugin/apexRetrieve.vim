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
let s:instructionPrefix = '||'

let s:MARK_SELECTED = "*"
let s:SELECTED_LINE_REGEX = '^\v(\s*)\V\('.s:MARK_SELECTED.'\)\v(\s*\w*)$'
							"\v enable super magic to avoid too many slashes
							"\s* - any number of white-space characters
							"\V - very no magic, to ignore anything which can be in s:MARK_SELECTED
							"use () to group in 3 groups, second group 'mark symbol' will be
							"dynamically removed later
let s:HIERARCHY_SHIFT = "--"

let s:ALL_METADATA_LIST_FILE = "describeMetadata-result.txt"

let b:PROJECT_NAME = ""
let b:PROJECT_PATH = ""
let b:SRC_PATH = ""
" loaded s:CACHED_META_TYPES looks like this:
"	{CustomObject: {XMLName:'CustomObject', DirName:'Objects', Suffix:'object', HasMetaFile:'false', InFolder:'false', ChildObjects:[CustomField, BusinessProcess,...]}}
let s:CACHED_META_TYPES = {} 

let s:BUFFER_NAME = 'vim-force.com Metadata Retrieve'

let s:SRC_DIR_NAME='src' " TODO name of src folder is also defined in apex.vim, consider merging


" open existing or load new file with metadata types
" retrieved list of supported metadata types is stored
" in ./vim-force.com folder under project root, next to ./src/
"
" param: filePath - path to any source file in force.com project structure
function! apexRetrieve#open(filePath)
	
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectName = projectPair.name
	let projectPath = projectPair.path
	"init header and length variables
	call s:init(projectPath)

	" check if buffer with file types already exist
	if exists("g:APEX_META_TYPES_BUF_NUM") && bufloaded(g:APEX_META_TYPES_BUF_NUM)
		execute 'b '.g:APEX_META_TYPES_BUF_NUM
	else "load types list and create new buffer
		let metaTypes = s:getMetaTypesList(projectName, projectPath, 0)
		if len(metaTypes) < 1
			"file does not exist, and load was abandoned
			return ""
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
		let b:SRC_PATH = apexOs#joinPath([projectPath, "src"])
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

		" Set the buffer name if not already set
		if bufname('%') != s:BUFFER_NAME
			exec 'file ' . fnameescape(s:BUFFER_NAME)
		endif

		" Define key mapping for current buffer
		exec 'nnoremap <buffer> <silent> t :call <SNR>'.s:sid.'_ToggleSelected()<CR>'
		"exec 'nnoremap <buffer> <silent> e :call <SNR>'.s:sid.'_ExpandCurrent()<CR>'
		" Define commands for current buffer
		"exec 'command! -buffer -bang -nargs=0 Expand :call <SNR>'.s:sid.'_ExpandSelected()'
		exec 'command! -buffer -bang -nargs=0 Retrieve :call <SNR>'.s:sid.'_RetrieveSelected()'

	endif

	" syntax highlight
	if has("syntax")
		syntax on
		exec "syn match ApexRetrieveInstructionsText '^\s*".s:instructionPrefix.".*'"
		exec "syn match ApexRetrieveInstructionsFooter '^\s*".s:instructionFooter."*$'"
		"exec 'syn match ApexRetrieveSelectedItem "^\v\s*\V'.s:MARK_SELECTED.'\v\s*\w*$"'
		exec 'syn match ApexRetrieveSelectedItem /'.s:SELECTED_LINE_REGEX.'/'
	endif

	exec "highlight link ApexRetrieveInstructionsText Constant"
	exec "highlight link ApexRetrieveInstructionsFooter Comment"
	exec "highlight link ApexRetrieveSelectedItem Keyword"


endfunction

" mark entry as Selected/Deselected
function! <SID>ToggleSelected()
  " Toggle type selection
	let lineStr = s:getCurrentLine()
	if s:isSelected(lineStr)
		"remove mark
		let lineStr = substitute(lineStr, s:SELECTED_LINE_REGEX, '\1\3', '')
						"remove group \2 (i.e. mark symbol) from current line
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
	let typesMap = s:loadChildrenOfType(typeName)
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
	let selectedLines = s:getSelectedTypes()
	if len(selectedLines) >0
		"insert child types of selected lines into buffer
	endif
endfunction

" for most types this method just calls apexAnt#bulkRetrieve
" but some (like Profile and PermissionSet) require special treatment
"
" return: temp folder path which contains subfolder with retrieved components
" ex: /tmp/temp
function! s:bulkRetrieve(typeName)
	let typeName = a:typeName
	if index(["Profile", "PermissionSet"], typeName) < 0
		return apexAnt#bulkRetrieve(b:PROJECT_NAME, b:PROJECT_PATH, typeName)
	else
		if "Profile" ==? typeName || "PermissionSet" ==? typeName
			" The contents of a profile retrieved depends on the contents of the
			" organization. For example, profiles will only include field-level
			" security for fields included in custom objects returned at the same
			" time as the profiles.
			" we have to retrieve all object types and generate package.xml
			" load children of given metadata type
			let typesMap = s:loadChildrenOfType("CustomObject")
			if len(typesMap) <=0
				call apexUtil#warning("Somethign went wrong. There are no objects available. Abort.")
				return ""
			endif
			" generate package.xml which contains Custom Objects and Profiles
			let package = apexMetaXml#packageXmlNew()
			let types = keys(typesMap)
			call add(types, "*") " add <members>*</members> option
			call apexMetaXml#packageXmlAdd(package, "CustomObject", types)
			call apexMetaXml#packageXmlAdd(package, typeName, ['*'])
			let tempDir = apexOs#createTempDir()
			let srcDir = apexOs#joinPath([tempDir, s:SRC_DIR_NAME])
			call apexOs#createDir(srcDir)
			let packageXmlPath = apexMetaXml#packageWrite(package, srcDir)

			" call Retrieve Ant task
			call apexAnt#refresh(b:PROJECT_NAME, tempDir)
			"now we expect some folders created under srcDir
			return srcDir
		endif	
	endif
endfunction

" retrieve components of all selected metadata types
function! <SID>RetrieveSelected()
	echo "Retrieve all selected items"
	let selectedTypes = s:getSelectedTypes()
	let retrievedTypes = {} "type-name => 1  - means type has been retrieved
	for l:type in selectedTypes

		let outputDir = s:bulkRetrieve(l:type)
		"echo "outputDir=".outputDir
		" now we need to sort out current type before downloading the next one
		" because target temp folder will be overwritten
		let typeDef = s:CACHED_META_TYPES[l:type]
		let dirName = typeDef["DirName"]
		let sourceFolder = apexOs#joinPath([outputDir, dirName])
		let targetFolder = apexOs#joinPath([b:SRC_PATH, dirName])

		let sourceFiles = apexOs#glob(sourceFolder . "/*")
		let targetFiles = apexOs#glob(targetFolder . "/*")
		
		"echo "sourceFiles=\n"
		"echo sourceFiles
		" copy files from loaded folder into project/src/dir-name folder checking
		" that we do not overwrite anything without user's permission
		
		if len(sourceFiles) < 1
			call apexUtil#warning(l:type . " has no members. SKIP.")
		else	
			" check that target folder exists
			if !isdirectory(targetFolder)
				call apexOs#createDir(targetFolder)
			endif

			let allConfirmed = 0
			for fPath in sourceFiles
				let fName = apexOs#splitPath(fPath).tail
				let targetFilePath = apexOs#joinPath([targetFolder, fName])
				"echo "check ".targetFilePath
				if filereadable(targetFilePath)
					" compare sizes
					let sourceSize = getfsize(fPath)
					let targetSize = getfsize(targetFilePath)
					if !allConfirmed && sourceSize != targetSize
						while 1
							echo " "
							call apexUtil#warning('File '.dirName.'/'.fName.' already exists.')
							echo 'New file size=' . sourceSize . ', Existing file size=' . targetSize
							let response = input('Overwrite (Y)es / (N)o / all / (A)bort / (C)ompare ? ')
							if index(['a', 'A', 'y', 'Y', 'n', 'N', 'all'], response) >= 0
								break " good answer, can continue with the main logic
							else
								if 'c' ==? response
									"run file comparison tool
									call ApexCompare(fPath, targetFilePath)
								else
									echo "\n"
									call apexUtil#warning("Permitted answers are: Y/N/A/all")
								endif
							endif	
						endwhile
						if 'a' ==? response
							"abort
							break
						elseif 'y' ==? response
							" proceed with overwrite
						elseif 'n' ==? response
							continue
						elseif 'all' ==? response
							" proceed with overwrite of all files
							let allConfirmed = 1
						else
							call apexUtil#warning("Something unexpected has happened. Aborting...")
							return
						endif	
					endif
				endif	
				call apexOs#copyFile(fPath, targetFilePath)
				" check if copy succeeded
				if !filereadable(targetFilePath)
					echoerr "Something went wrong, failed to write file ".targetFilePath.". Process aborted."
					return 
				else
					"mark current type is retrieved
					let retrievedTypes[l:type] = ['*']
				endif

			endfor
		endif "len(sourceFiles) < 1
	endfor
	"update package.xml
	if len(retrievedTypes) > 0
		let packageXml = apexMetaXml#packageXmlRead(b:SRC_PATH)
		let changeCount = 0
		for typeName in keys(retrievedTypes)
			let changeCount += apexMetaXml#packageXmlAdd(packageXml, typeName, retrievedTypes[typeName])
		endfor
		"write updated package.xml
		"echo packageXml
		if changeCount >0
			echohl WarningMsg
			let response = input('Update package.xml with new types [y/N]? ')
			echohl None
			if 'y' == response || 'Y' == response
				call apexMetaXml#packageWrite(packageXml, b:SRC_PATH)
			endif
		endif
	endif
	
endfunction

function! s:isSelected(lineStr)
	return a:lineStr =~ s:SELECTED_LINE_REGEX
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

function! s:getSelectedTypes()
	let lines = getline(s:headerLineCount +1, line("$"))
	let selectedLines = []
	"let l:count = 0

	for line in lines
		"echo "line=".line
		if s:isSelected(line)
			let line = substitute(line, s:MARK_SELECTED, "", "")
			"echo "selected line=".line
			let selectedLines = add(selectedLines, line)
		endif
		"let l:count = l:count +1
	endfor
	return selectedLines
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

" load children of given meta-type
" e.g. if type is "CustomObject" then all standard and custom object API 
" names will be returned 
" return: types map, see s:parseListMetadataResult() for details
function! s:loadChildrenOfType(typeName)
	let l:tmpfile = tempname()
	call apexAnt#listMetadata(b:PROJECT_NAME, b:PROJECT_PATH, l:tmpfile, a:typeName)
	if !filereadable(l:tmpfile)
		call apexUtil#warning( "No subtypes of ".lineStr." found.")
		return
	endif	
	" parse returned file into manageable format
	let typesMap = s:parseListMetadataResult(a:typeName, l:tmpfile)
	return typesMap
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
	let allMetaTypesFilePath = apexOs#joinPath([apex#getCacheFolderPath(a:projectPath), s:ALL_METADATA_LIST_FILE])

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

" call this method before any other as soon as Project Path becomes available
function! s:init(projectPath)
	let s:instructionFooter = '='
	let s:header = [
				\ "|| vim-force.com plugin - metadata retrieval",
				\ "||",
				\ "|| Select types to retrieve, then issue command :Retrieve" ,
				\ "|| ",
				\ "|| t=toggle Select/Deselect",
				\ "|| :Retrieve = retrieve selected types into the project folder",
				\ "|| ",
				\ "|| NOTE: cached list of metadata types is stored in: ",
				\ "||		 '".apexOs#joinPath([apex#getCacheFolderPath(a:projectPath), s:ALL_METADATA_LIST_FILE])."' file.",
				\ "||		To clear cached types delete this file and run :ApexRetrieve to reload fresh version.",
				\ "============================================================================="
				\ ]
	let s:headerLineCount = len(s:header)  
endfunction
"function! TestParseListMetadataResult(metadataType, fname)
"	call s:parseListMetadataResult(a:metadataType, a:fname)
"endfunction

" call apexRetrieve#open("SForce", "/Users/andrey/eclipse.workspace/Sforce - SFDC Experiments/SForce")

function! TestRetrieve()

	"call <SID>ToggleSelected()
	"call <SID>ExpandCurrent()
	"call <SID>RetrieveSelected()
endfunction
