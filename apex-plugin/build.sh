#!/bin/bash

#################################
# ant build script  file for Bash
# Maintainer:	Andrey Gavrikov 
# Version:		1.0
# Part of vim/force.com plugin

############################
# Command line parameters
# 1 - dest org name, ex: "org (sandbox1)" 
#     used to obtain access details and as target folder name (if alternateOrgFolder is not specified)
# 2 - path to folder with *.property files which contain SFDC orgs access
# 3 - path to SFDC project folder
# 4 - Action: "deploy" or "refresh", empty means "deploy"
baseFolder="$( cd "$( dirname "$0" )" && pwd )"


buildFile="$baseFolder/build.xml"
destOrgName=
propertiesPath=
projectFolder=
action=deploy
error=0

function usage {
	echo ""
	echo "parameter $1 is required"
	echo "usage: org-refresh.sh 'my sandbox name' '/path/to/properties/folder' '/path/to/project/folder' [deploy|refresh]"
	echo "where: "
    echo "     'my org (sandbox name)' - properties file name which contains login info and can be found at '/path/to/properties/folder'"
	echo "		deploy - use deploy action to push code to sfdc"
	echo "		refresh - refresh project from sfdc"
	echo ""
	exit 1	
}

if [ -n "$1" ]; then 	# -n tests to see if the argument is not empty, -z tests for zero length
	destOrgName=$1
	#echo "Using destination org: $destOrgName"
else
	usage "1 - dest org name"
fi

if [ -n "$2" ]; then
	propertiesPath=$2
else
	usage "2 - full path to folder which contains .properties files with access details"
fi

if [ -n "$3" ]; then 	# -n tests to see if the argument is not empty, -z tests for zero length
	projectFolder=$3
else
	usage "3 - full path to SFDC project folder"
fi
if [ -n "$4" ]; then 	# -n tests to see if the argument is not empty, -z tests for zero length
	action=$4
fi
echo "Using project folder: $projectFolder, destination org=\"$destOrgName\" propertiesPath=$propertiesPath and buildFile=$buildFile"

if [ $error -eq 1 ]; then
	exit 1
fi

# use Proxy if necessary
if [ -x ~/bin/network/init-proxy-variables.sh ]; then
	source ~/bin/network/init-proxy-variables.sh
fi

if [ "$action" == "deploy" ]; then
	ant  -buildfile "$buildFile" -Ddest.org.name="$destOrgName" -Dproperties.path="$propertiesPath" -Dproject.Folder="$projectFolder" deployUnpackaged
elif [ "$action" == "refresh" ]; then
	ant  -buildfile "$buildFile" -Ddest.org.name="$destOrgName" -Dproperties.path="$propertiesPath" -Dproject.Folder="$projectFolder" retrieveSource
else
	echo "invalid action $action"
	usage "parameter #4 - action must be either 'deploy' or 'refresh'"
fi	

