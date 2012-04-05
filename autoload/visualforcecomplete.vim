" File: visualforcecomplete.vim
" Author: Andrey Gavrikov 
" Version: 0.0.1
" Last Modified: 2012-03-05
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damamges resulting from the use of this
"            software.
"
" Part of vim/force.com plugin
" visualforcecomplete.vim - Omni Completion for Visualforce
" provides very basic VF tag name completion
"
let s:tagTypes = ["apex", "chatter", "flow", "ideas", "knowledge", "messaging", "site"]

function! visualforcecomplete#Complete(findstart, base)
    "findstart = 1 when we need to get the text length
	if a:findstart
	    " locate the start of the word
	    let line = getline('.')
	    let start = col('.') - 1
	    while start > 0 && line[start - 1] =~ '\a'
	      let start -= 1
	    endwhile
		"check if there is <apex: in front
		if start > 0
			let tagPrefix = s:getTagPrefix(line, start)
			"echomsg "start=".start." with prefix ".tagPrefix
			let prefixLen = len(tagPrefix)
			if prefixLen > 0
				let start = start - prefixLen
			endif	
		endif	
		"echomsg "start=".start
	    return start

	else "findstart = 0 when we need to return the list of completions
		" find tags matching with "a:base"
		let res = []
		let tagPrefix = s:getTagPrefix(a:base, 0)
		let prefixLen = len(tagPrefix)
		let hasPrefix = prefixLen > 0

		let matchBase = a:base
		let apexTags = []
		let tTypes = []

		" check if we have something like <apex:
		" for tagType in s:tagTypes
			" let tagTypeLen = len(tagType);
			" let tagPrefixLen  = tagTypeLen + 2 " <...:
			" if tagPrefixLen <= start && strpart(line, start - tagPrefixLen, start) == "<".tagType.":"
				" "we have  <apex: situation

			" endif	
		" endfor	
		if hasPrefix
			let matchBase = strpart(a:base, prefixLen)
			"tagPrefix looks like <apex:
			"extract component type
			let componentType = strpart(tagPrefix, 1, prefixLen -2) 
			"echomsg "componentType=".componentType
			let tTypes = [componentType]
			"load tags by prefix
			for tagType in tTypes
				"echomsg "tagType=".tagType
				for m in s:getTagsByType(tagType)
					if m =~ '^'.matchBase
						"echomsg "Match=".m
						call add (res, { 'word': s:formatCompetionForTag(tagType, m), 'abbr' : m, 'menu': tagType.' tag'})
					endif
				endfor
			endfor
		else
			" display tag prefixes
			let tTypes = s:tagTypes
			for tagType in tTypes
				"echomsg "tagType=".tagType
				call add (res, { 'word': tagType, 'menu': 'VF category'})
			endfor
		endif	
		"echomsg "matchBase=".matchBase
		"echomsg "tagPrefix=".tagPrefix

		
		return res
	endif
	
	
endfunction

function! s:formatCompetionForTag(tagType, tagName)
	return "<".a:tagType . ":" . a:tagName ."> </" .a:tagType . ":" . a:tagName . ">" 
endfunction	

function! s:getTagPrefix(str, start) 
	for tagType in s:tagTypes
		let tagPrefix = "<".tagType.":"
		let prefixLen = len(tagPrefix)
		let index = -1
		if a:start >0
			let index = stridx(a:str, tagPrefix, a:start - prefixLen)
		else
			let index = stridx(a:str, tagPrefix)	
		endif	
		if  index >=0
			"echomsg a:str." has prefix=".tagPrefix
			return tagPrefix
		endif	
	endfor	
	return "" " no prefix
endfunction

function! s:getApexTags()
	let apexTags = ["actionFunction", "actionPoller", "actionRegion", "actionStatus", "actionSupport",
				\	"attribute", "column", "commandButton", "commandLink", "component",
				\	"componentBody", "composition", "dataList", "dataTable", "define",
				\	"detail", "enhancedList", "facet", "flash", "form",
				\	"iframe", "image", "include", "includeScript", "inlineEditSupport",
				\	"inputCheckbox", "inputField", "inputFile", "inputHidden", "inputSecret",
				\	"inputText", "inputTextarea", "insert", "listViews", "message",
				\	"messages", "outputField", "outputLabel", "outputLink", "outputPanel",
				\	"outputText", "page", "pageBlock", "pageBlockButtons", "pageBlockSection",
				\	"pageBlockSectionItem", "pageBlockTable", "pageMessage", "pageMessages", "panelBar",
				\	"panelBarItem", "panelGrid", "panelGroup", "param", "relatedList",
				\	"repeat", "scontrol", "sectionHeader", "selectCheckboxes", "selectList",
				\	"selectOption", "selectOptions", "selectRadio", "stylesheet", "tab",
				\	"tabPanel", "toolbar", "toolbarGroup", "variable", "vote" ]

	return apexTags
endfunction	

function! s:getChatterTags()
	return ["feed", "feedWithFollowers", "follow", "followers"]
endfunction	

function! s:getFlowTags()
	return ["interview"]
endfunction	


function! s:getIdeasTags()
	return ["detailOutputLink", "listOutputLink", "profileListOutputLink"]
endfunction	


function! s:getKnowledgeTags()
	return ["articleCaseToolbar", "articleList", "articleRendererToolbar", "articleTypeList", "categoryList"]
endfunction	

function! s:getMessagingTags()
	return ["attachment", "emailHeader", "emailTemplate", "htmlEmailBody", "plainTextEmailBody", "", "", "", ""]
endfunction	

function! s:getSiteTags()
	return ["googleAnalyticsTracking", "previewAsAdmin"]
endfunction	

" @componentType ["apex", chatter", ...]
function! s:getTagsByType(componentType)
	if "apex" == a:componentType
		return s:getApexTags()
	elseif "chatter" == a:componentType
		return s:getChatterTags()
	elseif "flow" == a:componentType
		return s:getFlowTags()
	elseif "ideas" == a:componentType
		return s:getIdeasTags()
	elseif "knowledge" == a:componentType
		return s:getKnowledgeTags()
	elseif "messaging" == a:componentType
		return s:getMessagingTags()
	elseif "site" == a:componentType
		return s:getSiteTags()
	else
		return []
	endif	
endfunction	

function s:getAllTags()
	let allTags = []
	for tagType in tagTypes
		let allTags += s:getTagsByType(tagType)
	endfor	
	return allTags
endfunction	
