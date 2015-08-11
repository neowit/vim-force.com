" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexRetrieve.vim
" Last Modified: 2014-02-08
" Author: Andrey Gavrikov 
" Maintainers: 
"
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
		exec 'command! -buffer -bang -nargs=0 Reload :call <SNR>'.s:sid.'_ReloadFromRemote()'

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

		if "*CustomObject" == lineStr
			call apexUtil#warning("You used wildcard (*) against 'CustomObject' type.")
			call apexUtil#warning(" Please note - this will NOT include any standard objects.")
			call apexUtil#warning(" To retrieve Standard objects you must call :Expand and select each object type explicitly.")
			call apexUtil#warning(" See more details here: http://www.salesforce.com/us/developer/docs/daas/Content/commondeploymentissues.htm")
		endif	
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

	" clear cache
	let s:LOADED_CHILDREN_BY_ROOT_TYPE = {}

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


" remove current cache and reload from remote
function! <SID>ReloadFromRemote()
    let fPath = s:getMetadataResultFilePath(b:PROJECT_PATH)
    if filereadable(fPath)
        call delete(fPath)
        :bdelete
        call apexRetrieve#open(expand("%:p"))
    endif


endfunction

let s:LOADED_CHILDREN_BY_ROOT_TYPE = {}
"Returns: dictionary {xmlTypeName: [child-components]}
"e.g.: 
"{"CustomTab" : ["Account_Edit", "My_Object__c"]}
"{"CustomObject" : ["Account", "My_Object__c", ...]}
function! s:getCachedChildrenOfSelectedTypes(xmlTypeName)
	if has_key(s:LOADED_CHILDREN_BY_ROOT_TYPE, a:xmlTypeName)
		return s:LOADED_CHILDREN_BY_ROOT_TYPE[a:xmlTypeName]
	endif

	" cache seems to be empty, load it
	let firstSelectedLineNum = s:getFirstSelected()
	let selectedRootTypes = []
	let lineNum = firstSelectedLineNum
	let typeNames = []
	while lineNum <= line("$")
		let line = getline(lineNum)
		if s:isSelected(line) && match(line, s:HIERARCHY_SHIFT) < 0
			let lineStr = getline(lineNum)
			"remove mark if exist
			let lineStr = substitute(lineStr, s:MARK_SELECTED, "", "")
			let typeName = apexUtil#trim(lineStr)
			call add(typeNames, typeName)
		endif
		let lineNum += 1
	endwhile
	
	if !empty(typeNames)
		let specificTypesFilePath = tempname()
		call writefile(typeNames, specificTypesFilePath)
		" call tooling jar
		let resMap = {}
		let reEnableMore = 0
		try
			let reEnableMore = &more
			set nomore "disable --More-- prompt

			let resMap = apexTooling#listMetadata(b:PROJECT_NAME, b:PROJECT_PATH, specificTypesFilePath)
			if 'true' != resMap["success"]
				" stop from further attempts to repeat calls to jar in the
				" current request
				for typeName in typeNames
					if !has_key(s:LOADED_CHILDREN_BY_ROOT_TYPE, typeName)
						let s:LOADED_CHILDREN_BY_ROOT_TYPE[typeName] = []
					endif
				endfor
				return []
			endif
		finally
			if reEnableMore
				set more
			endif
		endtry	
	endif
	" parse result file
	if has_key(resMap, "resultFile")
		let resultFile = resMap["resultFile"] " path to file with JSON lines
		let membersByXmlType = {}
		if filereadable(resultFile)
			for line in readfile(resultFile, '', 10000) " assuming metadata types file will never contain more than 10K lines
				let json = eval(line)
				let xmlTypeName = keys(json)[0]
				let membersByXmlType[xmlTypeName] = json[xmlTypeName]
			endfor
		endif
	else
		let membersByXmlType = {}
	endif
	" make sure that we accounted for all requested type names
	for typeName in typeNames
		if !has_key(membersByXmlType, typeName)
			let membersByXmlType[typeName] = []
			call apexUtil#warning("[3] " . typeName . " has no members. SKIP.")
		endif
	endfor
	" finally store loaded memebrs in cache
	let s:LOADED_CHILDREN_BY_ROOT_TYPE = membersByXmlType
	if has_key(membersByXmlType, a:xmlTypeName) && !empty(membersByXmlType[a:xmlTypeName])
		return membersByXmlType[a:xmlTypeName]
	endif
	return []
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
		exe firstLine.','.(firstLine + l:count -1).'delete'
	endif
	return l:count

endfunction

"load children of metadata type in given line
"Returns: list of children
function! s:expandOne(lineNum)
	return s:expandOneToolingJar(a:lineNum)
endfunction

"load children of metadata type in given line
"Returns: list of children
function! s:expandOneToolingJar(lineNum)
	let lineNum = a:lineNum

	let lineStr = getline(lineNum)
	"remove mark if exist
	let lineStr = substitute(lineStr, s:MARK_SELECTED, "", "")
	let typeName = apexUtil#trim(lineStr)

	" load children of given metadata type
	let typesList = s:getCachedChildrenOfSelectedTypes(typeName)
	
	if len(typesList) > 0
		let typesList = sort(typesList)
		let shiftedList = []
		" append types below current
		for curType in typesList
			call add(shiftedList, s:HIERARCHY_SHIFT . curType)
		endfor
		call append(lineNum, shiftedList)
	endif
	return typesList
endfunction

function! <SID>RetrieveSelected()
	"echo "Retrieve all selected items"
	"go through root meta types
	let selectedTypes = s:getSelectedTypes()
	"{'ApexClass': ['asasa.cls', 'adafsd.cls'], 'AnalyticSnapshot': ['*'], 'ApexComponent': ['*']}

	call s:retrieveSelectedToolingJar(selectedTypes)
endfunction
"
" retrieve components of all selected metadata types
function! s:retrieveSelectedToolingJar(selectedTypes)
	let selectedTypes = a:selectedTypes
	" generate "specificTypes" file
	let lines = []
	for [key, value] in items(selectedTypes)
		" {"XMLName": "Profile", "members": []}
		" {"XMLName": "ApexClass", "members": ["A_Fake_Class"]}
		let json = {"XMLName": key, "members" : value}
		let jsonStr = substitute(string(json), "'", '"', "g")
		call add(lines, jsonStr)
	endfor	
	
	if !empty(lines)
		let specificTypesFilePath = tempname()
		call writefile(lines, specificTypesFilePath)
		" call tooling jar
		let reEnableMore = 0
		try
			let reEnableMore = &more
			set nomore "disable --More-- prompt

			let resMap = apexTooling#bulkRetrieve(b:PROJECT_NAME, b:PROJECT_PATH, specificTypesFilePath, "json", "")
			if 'true' != resMap["success"]
				return {}
			endif
		finally
			if reEnableMore
				set more
			endif
		endtry	
		" extract outputDir from responseFilePath
		let outputDir = resMap["resultFolder"]
		let retrievedTypes = {}
		
		for l:type in keys(selectedTypes)
			let typeDef = s:CACHED_META_TYPES[l:type]
			let dirName = typeDef["DirName"]
			let sourceRoot = apexOs#joinPath(outputDir, "unpackaged")
			let sourceFolder = apexOs#joinPath(sourceRoot, dirName)
			let sourceFolderPathLen = len(sourceFolder)
			let targetFolder = apexOs#joinPath(b:SRC_PATH, dirName)
			"echo "sourceFolder=" . sourceFolder
			"echo "targetFolder=" . targetFolder

			let sourceFiles = apexOs#glob(sourceFolder . "/**")
			let targetFiles = apexOs#glob(targetFolder . "/**")
			"echo "sourceFiles=" . string(sourceFiles)
			"echo "targetFiles=" . string(targetFiles)
			if len(sourceFiles) < 1
				call apexUtil#warning("[1] " . l:type . " has no members. SKIP.")
			else	
				" copy files
				let allConfirmed = 0
				for fPath in sourceFiles
					let fName = apexOs#splitPath(fPath).tail
					" calculate path relative sourceFolder
					" i.e. if source path is
					" /some/folder/unpackaged/classes/myclass.cls
					" then we need relativeTargetPath = classes/myclass.cls 
					let relativeTargetPath = strpart(fPath, sourceFolderPathLen + 1)
					let targetFilePath = apexOs#joinPath(targetFolder, relativeTargetPath)
					let targetFileParentDir = apexOs#splitPath(targetFilePath).head
					
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
										call apexUtil#compareFiles(fPath, targetFilePath)
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
					
					"echo "fPath=" . fPath . "; targetFilePath=" .targetFilePath

					if isdirectory(fPath)
						if !isdirectory(targetFilePath)
							call apexOs#createDir(targetFilePath)
						endif
					else
						if !isdirectory(targetFileParentDir)
							call apexOs#createDir(targetFileParentDir)
						endif
						call apexOs#copyFile(fPath, targetFilePath)
						" check if copy succeeded
						if !filereadable(targetFilePath)
							echoerr "Something went wrong, failed to write file ".targetFilePath.". Process aborted."
							checktime "make sure that external changes are reported
							return 
						else
							"mark current type is retrieved
							let members = selectedTypes[l:type]
							let retrievedTypes[l:type] = members
						endif
					endif

				endfor
			endif "len(sourceFiles) < 1
		endfor
		
		checktime "make sure that external changes are reported

		"update package.xml
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
	endif "if !empty(lines)
endfunction

" load Dictionary of available meta-types
" Args:
" projectName: name of .properties file name
" projectPath: full path to project folder to load/save cache
" forceLoad: if true then cached file will be ignored and metadata reloaded
"			from server
" Return:
" map of metadata which looks like this:
"{'CustomPageWebLink': {'InFolder': 'false', 'DirName': 'weblinks','ChildObjects': [], 'HasMetaFile': 'false', 'Suffix': 'weblink'}, 
"'OpportunitySharingRules': {'InFolder': 'false', 'DirName': 'opportunitySharingRules', 
"		'ChildObjects': ['OpportunityOwnerSharingRule', 'OpportunityCriteriaBasedSharingRule'], 
"		'HasMetaFile': 'false', 'Suffix': 'sharingRules'}, 
"'CustomLabels': {'InFolder': 'false', 'DirName': 'labels', 'ChildObjects':['CustomLabel'], 'HasMetaFile': 'false', 'Suffix': 'labels'}, 
" …}
"
"
function! s:getMetaTypesMap(projectName, projectPath, forceLoad)
	return s:getMetaTypesMapToolingJar(a:projectName, a:projectPath, a:forceLoad)
endfunction

"depending on the current command set metadata description can be in two
"different formats
function! s:getMetadataResultFile()
	return "describeMetadata-result.js"
endfunction

function! s:getMetadataResultFilePath(projectPath)
	return apexOs#joinPath([apex#getCacheFolderPath(a:projectPath), s:getMetadataResultFile()])
endfunction

"load metadata description using toolingJar
" parse metadata definition file and return result in following format
"
"{'CustomPageWebLink': {'InFolder': 'false', 'DirName': 'weblinks','ChildObjects': [], 'HasMetaFile': 'false', 'Suffix': 'weblink'}, 
"'OpportunitySharingRules': {'InFolder': 'false', 'DirName': 'opportunitySharingRules', 
"		'ChildObjects': ['OpportunityOwnerSharingRule', 'OpportunityCriteriaBasedSharingRule'], 
"		'HasMetaFile': 'false', 'Suffix': 'sharingRules'}, 
"'CustomLabels': {'InFolder': 'false', 'DirName': 'labels', 'ChildObjects':['CustomLabel'], 'HasMetaFile': 'false', 'Suffix': 'labels'}, 
"…}
function! s:getMetaTypesMapToolingJar(projectName, projectPath, forceLoad)
	let allMetaTypesFilePath = s:getMetadataResultFilePath(a:projectPath)

	if !filereadable(allMetaTypesFilePath) || a:forceLoad
		let res = apexTooling#loadMetadataList(a:projectName, a:projectPath, allMetaTypesFilePath)
		if 'true' != res["success"]
			return {}
		endif
	endif
	let typesMap = {}
	for line in readfile(allMetaTypesFilePath, '', 10000) " assuming metadata types file will never contain more than 10K lines
		" replace all json false/true with 'false'/'true'
		let lineFixed = substitute(line, ":\\s*true", ": 'true'", "g")
		let lineFixed = substitute(lineFixed, ":\\s*false", ": 'false'", "g")

		try
			let lineMap = eval(lineFixed)
		catch
			" dump debug info
            echo "failed ot convert JSON to vim dictionary"
			echo "before"
			echo line
			echo "after"
			echo lineFixed

			return {}
		endtry
		let typesMap[lineMap["XMLName"]] = lineMap
	endfor
	" store in cache
	let s:CACHED_META_TYPES = typesMap
	return typesMap

endfunction

"reverse map returned by s:getMetaTypesMap and use folder names as keys and
"XML names as values
" Return:
" {'weblinks': 'CustomPageWebLink', 'labels' : 'CustomLabels'}
function! apexRetrieve#getTypeXmlByFolder(projectName, projectPath, forceLoad)
	let typesMap = s:getMetaTypesMap(a:projectName, a:projectPath, a:forceLoad)
	let xmlNameByDirName = {}
	for xmlName in keys(typesMap)
		let dirName = typesMap[xmlName]['DirName']

		let xmlNameByDirName[dirName] = xmlName
	endfor
	return xmlNameByDirName
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

" if file does not exist then plugin will attempt loading list
" of supported metadata types from SFDC
"
" return: list of all supported metadata types
function! s:getMetaTypesList(projectName, projectPath, forceLoad)

	let typesMap = s:getMetaTypesMap(a:projectName, a:projectPath, a:forceLoad)
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
				\ "|| :Reload = discard existing local cache of metadata types and reload them from remote Org",
				\ "|| ",
				\ "|| NOTE: cached list of CORE metadata types is stored in: ",
				\ "||		 '".s:getMetadataResultFilePath(a:projectPath)."' file.",
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
