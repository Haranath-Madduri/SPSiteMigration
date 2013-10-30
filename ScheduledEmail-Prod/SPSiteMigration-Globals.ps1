
# Dot-Source if we ae on a new thread:
if($global:SPSGlobalsSet -ne $true)									# A check to keep other scripts from repeating global configuration.
{
	$global:AutomationNodesXML 	= [System.Xml.XmlNodeList] $null
	$global:FailureSequences   	= [System.Xml.XmlElement] $null
	$global:GlobalSettings    	= [System.Xml.XmlElement] $null
	
	$global:SPSGlobalsSet 		= $true								# Set SPSGlobalsSet to true to keep other scripts from dot-sourcing (infinite loop)
	
	. .\SPSiteMigration-Configuration.ps1
	. .\SPSiteMigration-Delist.ps1
	. .\SPSiteMigration-Export.ps1
	. .\SPSiteMigration-Import.ps1
	. .\SPSiteMigration-Redirection.ps1
	. .\SPSiteMigration-Rollback.ps1
	. .\SPSiteMigration-SQL.ps1
	. .\SPSiteMigration-Tests.ps1
	. .\SPSiteMigration-Upgrade.ps1
	. .\SPSiteMigration-Upload.ps1
	. .\SPSiteMigration-Workflows.ps1
	. .\StoredProcExecutionScript.ps1
	. .\SendEmail.ps1
	. .\Functions.ps1
	#. .\SPSiteMigration-LockSite.ps1
}