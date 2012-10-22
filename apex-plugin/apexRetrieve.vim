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

if exists("g:loaded_apex_retrieve") && !exists ("g:vim_force_com_debug_mode") || &compatible || stridx(&cpo, "<") >=0
	"<SID> requires that the '<' flag is not present in 'cpoptions'.
	finish
endif
let g:loaded_apex_retrieve = 1
let s:instructionPrefix = '||'

let s:MARK_SELECTED = "*"
let s:SELECTED_LINE_REGEX = '^\v(\s*)\V\('.s:MARK_SELECTED.'\)\v(\s*\w*.*)$'
							"\v enable super magic to avoid too many slashes
							"\s* - any number of white-space characters
							"\V - very no magic, to ignore anything which can be in s:MARK_SELECTED
							"use () to group in 3 groups, second group 'mark symbol' will be
							"dynamically removed later
let s:HIERARCHY_SHIFT = "--"
let s:CHILD_LINE_REGEX = '^\v(\s*)\V\('.s:HIERARCHY_SHIFT.'\)\v(\s*\w*.*)$'


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
		exec 'command! -buffer -bang -nargs=0 Expand :call <SNR>'.s:sid.'_ExpandSelected()'

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
	let currentLineNum = line('.')
	let lineStr = s:getCurrentLine()
	let removeParentMark = 0
	if s:isSelected(lineStr)
		"remove mark
		let lineStr = s:setSelection(lineStr, 0)
	else
		"add mark
		let lineStr = s:setSelection(lineStr, 1)
		let removeParentMark = 1
	endif
	call s:setCurrentLine(lineStr)

	"remove selection from parent component
	if removeParentMark && lineStr =~ s:HIERARCHY_SHIFT
		"selected element is a child of something else
		"remove mark from parent element
		let topLine = s:headerLineCount
		"find parent
		let lineNum = s:getParentLineNum(currentLineNum)
		
		if lineNum > 0
			let lineStr =  getline(lineNum)
			if s:isSelected(lineStr)
				let lineStr = s:setSelection(lineStr, 0)
				call setline(lineNum, lineStr)
			endif
		endif
	end	
endfunction

" find line number of parent element of given line
" if current line is level 1, i.e. child then go up
" until we found line at level 0
"Args:
"param: lineNum - child line to start with
"Return:
" parent line number of -1 if no parent detected
function! s:getParentLineNum(lineNum)
	let topLine = s:headerLineCount
	let lineNum = a:lineNum -1
	"find parent
	let found = 0
	while lineNum > topLine
		let lineStr =  getline(lineNum)
		if lineStr =~ s:HIERARCHY_SHIFT
			let lineNum -= 1
		else
			let found = 1
			break
		endif
	endwhile
	if found
		return lineNum
	endif
	return -1 "current line is not child line

endfunction

" set or remove selection mark from given text
"Args:
"param: enable if 1 then add selection mark, otherwise remove selection mark
function! s:setSelection(lineStr, on)
	let lineStr = a:lineStr
	if !a:on
		if s:isSelected(lineStr)
			"remove mark
			let lineStr = substitute(lineStr, s:SELECTED_LINE_REGEX, '\1\3', '')
							"remove group \2 (i.e. mark symbol) from current line
		endif
	else
		"add mark
		let lineStr = s:MARK_SELECTED . lineStr
	endif
	return lineStr
endfunction

" retrieve children of selected component
" get detail information about metadata components of selected type
function! <SID>ExpandCurrent()
	"echo "load children of current line"

	let lineNum = line('.')
	call s:deleteChildren(lineNum)
	call s:expandOne(lineNum)
endfunction


function! <SID>ExpandSelected()
	"echo "load children of all selected items"
	"check if there are selected lines
	let firstSelectedLineNum = s:getFirstSelected()
	if firstSelectedLineNum < 1
		echo "nothing selected"
		return 0
	endif
	let lineNum = firstSelectedLineNum

	"remove all children of selected root types
	while lineNum <= line("$")
		let line = getline(lineNum)
		"find all selected items of level 0, ignore all Children
		if s:isSelected(line) && match(line, s:HIERARCHY_SHIFT) < 0
			"remove existing children
			let deletedLineCount = s:deleteChildren(lineNum)
			"echo "Deleted ".deletedLineCount." lines "
		endif
		let lineNum += 1
	endwhile

	"load children of each selected root type
	let lineNum = firstSelectedLineNum
	let hasSelectedRootTypes = 0
	while lineNum <= line("$")
		let line = getline(lineNum)
		if s:isSelected(line) && match(line, s:HIERARCHY_SHIFT) < 0
			"now insert new children
			let typeMap = s:expandOne(lineNum)
			let shiftSize = len(typeMap)
			if shiftSize >0
				let lineNum += shiftSize
			else "no members of selected type available
				let lineNum += 1
			endif
			let hasSelectedRootTypes = 1
		else
			let lineNum += 1
		endif
	endwhile
	if hasSelectedRootTypes < 1
		echo "No Root types selected"
	endif

endfunction

"1delete
"%delete
"1,$delete
"Delete children of given line
"
function! s:deleteChildren(lineNum)
	let l:count = 0
	let firstLine = a:lineNum +1
	for lineStr in getline(firstLine, line("$"))
		"echo "lineStr=".lineStr
		if lineStr =~ s:CHILD_LINE_REGEX
			let l:count += 1
			"echo "to be deleted"
		else
			"echo "reached the end of children"
			break
		endif
	endfor	
	"echo "count=".l:count
	if l:count > 0
		exe firstLine.','.(firstLine + l:count).'delete'
	endif
	return l:count

endfunction

"load children of metadata type in given line
function! s:expandOne(lineNum)
	let lineNum = a:lineNum

	let lineStr = getline(lineNum)
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
	return typesMap
endfunction

" for most types this method just calls apexAnt#bulkRetrieve
" but some (like Profile and PermissionSet) require special treatment
"
" return: temp folder path which contains subfolder with retrieved components
" ex: /tmp/temp
" Args:
" typeName: name of currently retrieved type, ex: ApexClass
" members - list of members ot retrieve, ex: ['MyClass1.cls', 'MyClass2.cls']
" allTypeMap - map of all types with members selected by user
"	this map is relevan for things like Profile & PermissionSet
function! s:bulkRetrieve(typeName, members, allTypeMap)
	let typeName = a:typeName
	let members = a:members
	if index(["Profile", "PermissionSet"], typeName) < 0 && members == ['*']
		return apexAnt#bulkRetrieve(b:PROJECT_NAME, b:PROJECT_PATH, typeName)
	elseif "Profile" ==? typeName || "PermissionSet" ==? typeName
		" The contents of a profile retrieved depends on the contents of the
		" organization. For example, profiles will only include field-level
		" security for fields included in custom objects returned at the same
		" time as the profiles.
		" we have to retrieve all object types and generate package.xml
		" load children of given metadata type
		" generate package.xml which contains Custom Objects and Profiles
		let package = apexMetaXml#packageXmlNew()
		if has_key(a:allTypeMap, "CustomObject")
			"call extend(types, a:allTypeMap["CustomObject"]) " add <members>...</members> option
			let customObjTypes = a:allTypeMap["CustomObject"]
		else
			let typesMap = s:loadChildrenOfType("CustomObject") "map of types with service info like file name, etc
																"each key is API Name of custom object
			if len(typesMap) <=0
				call apexUtil#warning("Something went wrong. There are no objects available. Abort.")
				return ""
			endif
			let customObjTypes = keys(typesMap) "names of all custom objects retrieved above"
			"no specific CustomObject types selected, use all
			"call add(types, "*") " add <members>*</members> option
		endif
		call apexMetaXml#packageXmlAdd(package, "CustomObject", customObjTypes)
		call apexMetaXml#packageXmlAdd(package, typeName, members)
		let tempDir = apexOs#createTempDir()
		let srcDir = apexOs#joinPath([tempDir, s:SRC_DIR_NAME])
		call apexOs#createDir(srcDir)
		let packageXmlPath = apexMetaXml#packageWrite(package, srcDir)

		" call Retrieve Ant task
		call apexAnt#refresh(b:PROJECT_NAME, tempDir)
		"now we expect some folders created under srcDir
		return srcDir
	else 
		"single type name with selected members
		return s:retrieveOne(typeName, members)
	endif
endfunction

" load selected members of given type
"Args:
"typeName - meta type name like: 'CustomObject' or 'ApexClass'
"members - list of members of given meta type, ex: ['MyClass.cls', 'MyController.cls']
function! s:retrieveOne(typeName, members)
	let package = apexMetaXml#packageXmlNew()
	call apexMetaXml#packageXmlAdd(package, a:typeName, a:members)
	let tempDir = apexOs#createTempDir()
	let srcDir = apexOs#joinPath([tempDir, s:SRC_DIR_NAME])
	call apexOs#createDir(srcDir)
	let packageXmlPath = apexMetaXml#packageWrite(package, srcDir)

	" call Retrieve Ant task
	call apexAnt#refresh(b:PROJECT_NAME, tempDir)
	"now we expect some folders created under srcDir
	return srcDir

endfunction

" retrieve components of all selected metadata types
function! <SID>RetrieveSelected()
	"echo "Retrieve all selected items"
	"go through root meta types
	let selectedTypes = s:getSelectedTypes()
	"{'ApexClass': ['asasa.cls', 'adafsd.cls'], 'AnalyticSnapshot': ['*'], 'ApexComponent': ['*']}

	echo selectedTypes

	let retrievedTypes = {} "type-name => 1  - means type has been retrieved
	for l:type in keys(selectedTypes)
		let members = selectedTypes[l:type]
		"members can be a list of Child Types or constant list ['*']

		let outputDir = s:bulkRetrieve(l:type, members, selectedTypes)
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
					let retrievedTypes[l:type] = members
				endif

			endfor
		endif "len(sourceFiles) < 1
	endfor
	"now go through individual elements on level 1
	"ex: individual Object or class names
	
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

"Args:
"param: a:1 - first line to start looking
"Return:
"number of first selected line or 0 if no selection found
function! s:getFirstSelected(...)
	let startLine = s:headerLineCount +1
	if a:0 >0
		let startLine = a:1
	endif
	let lineNum = startLine
	for lineStr in getline(startLine, line("$"))
		if s:isSelected(lineStr)
			return lineNum
		endif
		let lineNum += 1
	endfor
	return 0 "nothing found

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

"remove all marks line selection '*' or hierarchy shift '--'
function! s:removeMarks(line)
	let cleanStr = s:setSelection(a:line, 0) " remove *
	let cleanStr = substitute(cleanStr, s:CHILD_LINE_REGEX, '\1\3', '') " remove --
	return cleanStr
endfunction

" map of selected types
"Return:
" {"type-name1" -> "*", "type-name2" -> ["name1", "name2"]}
"ex:
" {"ApexPage" : ["*"], "ApexClass" : ["MyClass1.cls", "MyClass2.cls"]}
"
function! s:getSelectedTypes()
	let selectedLines = {}

	let lineNum = s:headerLineCount+1
	while lineNum <= line("$")
		let line = getline(lineNum)
		if s:isSelected(line)
			let typeStr = s:removeMarks(line)
			if line =~ s:HIERARCHY_SHIFT
				"this line is level 1
				let parentNum = s:getParentLineNum(lineNum)
				let parentTypeStr = getline(parentNum)

				let typeList = []
				if has_key(selectedLines, parentTypeStr)
					let typeList = selectedLines[parentTypeStr]
				endif
				call add(typeList, typeStr)
				let selectedLines[parentTypeStr] = typeList
			else
				"this line is level 0
				let selectedLines[typeStr] = ["*"]
			endif
		endif
		let lineNum += 1
	endwhile
	return selectedLines
endfunction

function! s:SID()
  " Return the SID number for this file
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
		"echo 'line='.line
		let items = split(line, ':')
		if len(items) < 2
			continue
		endif

		let key = apexUtil#trim(items[0])
		let value = apexUtil#trim(items[1])
		"echo 'key='.key.' value='.value

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
		call apexUtil#warning( "No subtypes of ".a:typeName." found.")
		return {}
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
				\ "|| :Expand = retrieve children of selected types for further selection",
				\ "|| :Retrieve = retrieve selected types into the project folder",
				\ "|| ",
				\ "|| NOTE: cached list of CORE metadata types is stored in: ",
				\ "||		 '".apexOs#joinPath([apex#getCacheFolderPath(a:projectPath), s:ALL_METADATA_LIST_FILE])."' file.",
				\ "||		To clear cached types delete this file and run :ApexRetrieve to reload fresh version.",
				\ "============================================================================="
				\ ]
	let s:headerLineCount = len(s:header)  
endfunction

function! TestRetrieve()

	"call <SID>ToggleSelected()
	"call <SID>ExpandCurrent()
	"call <SID>RetrieveSelected()
endfunction
