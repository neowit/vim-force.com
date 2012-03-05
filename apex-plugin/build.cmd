rem ant build script  file for Windows
rem Maintainer:	Andrey Gavrikov 
rem Version:		1.0
rem Part of vim/force.com plugin

@echo off
rem ############################
rem # Command line parameters
rem # 1 - dest org name, ex: "org (sandbox1)" 
rem # 2 - path to folder with *.properties files which contain SFDC orgs access
rem # 3 - path to SFDC project folder
rem # 4 - Action: "deploy" or "refresh", empty means "deploy"

set destOrgName=%1
set propertiesPath=%2
set projectFolder=%3
set action=%4

set baseFolder=%~dp0

set buildFile=%baseFolder%build.xml
:: echo baseFolder = %baseFolder%
:: echo buildFile = %buildFile%

:: escape spaces - replace ' \' with '/'
set buildFile=%buildFile:\=/%
set propertiesPath=%propertiesPath:\=/%

if "%action%"=="deploy" goto deploy
	
if "%action%"=="refresh" goto refresh

@echo off
echo invalid action '%action%'
goto usage


:usage
echo usage: 
echo parameter #1 - dest org name, ex: "my sandbox name" 
echo parameter #2 - path to folder with *.properties files which contain SFDC orgs access
echo parameter #3 - path to SFDC project folder
echo parameter #4 - action must be either 'deploy' or 'refresh'
echo ex: 
echo build.cmd "my sandbox name" "t:" "c/temp/MyProject" "refresh"
goto end

:deploy
    ant  -buildfile "%buildFile%" -Ddest.org.name=%destOrgName% -Dproperties.path="%propertiesPath%" -Dproject.Folder=%projectFolder% deployUnpackaged
goto end

:refresh
	ant  -buildfile "%buildFile%" -Ddest.org.name=%destOrgName% -Dproperties.path="%propertiesPath%" -Dproject.Folder=%projectFolder% retrieveSource
goto end


:end
