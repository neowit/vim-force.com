# Vim plugin for developing on force.com      

salesforce.com / force.com plugin for Vim version 7.3 or later.  

##### Update July 2015  
If you do not get code coverage data when running `:ApexTestWithCoverage` using
one of `meta-*` flags then you are most likely affected by a 
[bug in Metadata API Summer'15](http://salesforce.stackexchange.com/questions/84797/metadata-deploy-test-code-coverage-report-is-broken-in-metadata-api-v34-0-sum).  
Workaround 1: use `:ApexTestWithCoverage` with `tooling-sync` or `tooling-async` flag.  
Workaround 2: fall back to [tooling-force.com-0.3.3.3.jar](https://github.com/neowit/tooling-force.com/releases/tag/v0.3.3.3). 
Note: you will lose some of newer functions.  

##### Update March 2015  
If you are getting `Internal Server Error` when trying to deploy/save list of files which contain both Aura bundle(s) and Apex Class/Page then you are most likely affected by what appears to be a bug in Spring'15. 
Current workaround is to deploy Apex Classes/Pages first (:ApexDeployOne or :ApexDeployOpen or :ApexDeployStaged) and then call :ApexDeploy or :ApexSave as usual.

#### Update Oct. 2014  
Best way to take advantage of [Apex code completion](http://youtu.be/u-6JQNuWRdE) is to use "server" mode.  
If you are using server mode on MS Windows then you must have python available to vim.
Read `:help server-mode` in vim-force.com documentation carefully.

##### Update Feb. 2014  
'master' branch of vim-force.com is no longer based on Ant and [force.com migration tool](http://www.salesforce.com/us/developer/docs/daas/). This version requires config changes, see `:help force.com-installation`, `:help g:apex_tooling_force_dot_com_path` and `:help force.com-config-example`.  
If you want to continue using Ant + ant-salesforce.jar then switch to [ant-based](https://github.com/neowit/vim-force.com/tree/ant-based) branch.  



## DESCRIPTION                                             

vim-force.com plugin is a bunch of .vim scripts that allow to develop on force.com 
platform using Vim.

It is designed for those who do not feel productive in Force.com IDE for Eclipse.

General vim-force.com overview - http://www.youtube.com/watch?v=x5zKA6V__co  
`:ApexRetrieve` command demo - http://youtu.be/umO86ji2Iqw  
`:ApexStage` command demo - http://youtu.be/zQg8LORh8uc  
Apex Code completion demo - http://youtu.be/u-6JQNuWRdE

Other vim plugins recommended for use alongside vim-force.com plugin  
* FuzzyFinder - http://www.youtube.com/watch?v=EtiaXVnTA4g  
* SnipMate - http://www.youtube.com/watch?v=Ri_DP1sRn2o  
  - or [UltiSnips](http://vimcasts.org/episodes/meet-ultisnips/) - a more advanced alternative to SnipMate  
* NERDTree - http://www.youtube.com/watch?v=d93o9qAqIhE  
* TagList - http://www.youtube.com/watch?v=Suk45FHU6s8  
* TagBar (alternative to TagList) - [screenshot](https://f.cloud.github.com/assets/115889/378070/f8d241b0-a513-11e2-802e-d4419aac586d.png)

## FEATURES

* Build/Save to SFDC
  - with error reporting
  - "Run test"
    * Execute unit tests in all modified files
    * Execute unit tests in a selected Class
    * Execute *selected* test method in a selected Class
    * Display [code coverage](https://f.cloud.github.com/assets/552057/2147462/89eec2b0-93d2-11e3-9207-432ef8d90763.png) after running test
	

* Deploy from one Org to Another

* Delete selected metadata from SFDC

* Execute Anonymous
  - whole buffer or selected lines  

* Execute [SOQL query](http://youtu.be/RhjJVMh-50I)
  - supports Partner and Tooling APIs
          
* Persistent "Stage" for cherry-picking and re-using list of components to be deployed or deleted

* Load/update metadata from SFDC
  - Retrieve All or Selected components of given metadata type.  
Support for metadata types that reside inside folders (e.g. Document, Dashboard or Report) is limited because requires querying data (in addition to metadata).

* Create triggers/classes/pages

* Refresh project from SFDC

* Search
  - find word in classes/triggers  
  - find word everywhere  
  - find visual selection  

* Syntax highlighting
  - supports syntax highlighting of Apex Classes, Triggers, Pages, JS Resources

* List candidates for [auto-completion](http://youtu.be/u-6JQNuWRdE) in Apex classes. Invoked using vim omni-completion: `Ctrl-X,Ctrl-O`


* List candidates (field names, object types, relationships, etc) for [auto-completion](http://youtu.be/rzqgXV3Gx0s) in SOQL expressions. Invoked using vim omni-completion: `Ctrl-X,Ctrl-O`
  
* Most commands (where it makes sense) can be run against different orgs without leaving current project.  
e.g.   
`:ApexQuery` will run selected SOQL query against the Org configured for current project  
`:ApexQuery <api> MyOtherOrg` will run the same query against 'MyOtherOrg'.  
Org name supports auto completion.

* Handling content of zipped .resource files
	- useful when working with rich UIs with lots of javascript and CSS files   

* Basic (really basic) Visualforce code completion
	- try following in .page file  
      `< Ctrl-X,Ctrl-U`  
      `<apex: Ctrl-X,Ctrl-U`  
      `<chatter Ctrl-X,Ctrl-U`
	
* Initial support for aura/lightning
	- insert/delete/update/query for all aura file types is fully supported but there is currently no file templates or wizard to create various types of aura files. Use standard vim/file-system tools to create relevant files/folders.

## LIMITATIONS

Salesforce.com API does not (in most cases) report error line numbers
in Visualforce pages, making it impossible to go-to actual problem line if
compile/save fails due to a syntax error.

Apex/SOQL auto-completion is a work in progress and there are many cases when it may not work as expected.

## Installation/System requirements 

Before vim-force.com plugin can be used the following requirements must be met:

1. Vim version 7.3 or later with `:set nocompatible`  

2. Java JDK/JRE, Version 7 or greater  
   - Oracle JDK
     http://www.oracle.com/technetwork/java/javase/downloads/index.html       
JDK is not strictly required, JRE will suffice.  
  
3. Tooling-force.com  
   [download jar from 'releases' page](https://github.com/neowit/tooling-force.com) 
   

4. the rest see in vim doc `:help force.com-system-requirements` or directly in [force.com.txt](https://github.com/neowit/vim-force.com/blob/master/doc/force.com.txt).


## RECOMMENDED-PLUGINS                             

There is a number of great Vim plugins which you may want to consider  
- Fugitive - git support  
- unite.vim or ctrl-p - quick file/buffer open  
- NERDTree - project/file-system browsing  
- Pathogen - manage individually installed plugins in ~/.vim/bundle  
- UltiSnip - implements some of TextMate's snippets features in Vim  
- TagBar - a source code browser plugin for Vim  


##CREDITS                                                     

Author: Andrey Gavrikov 

Credit must go out to Bram Moolenaar and all the Vim developers for
making the world's best editor (IMHO). I also want to thank everyone who
helped and gave me suggestions. I wouldn't want to leave anyone out so I
won't list names.

