Function Set-SiteReadOnly
{
    Param([parameter(Mandatory = $true)] [string] $SourceURL)
	
    Write-Host 'Making Site ReadOnly for '$SourceURL
	
    $AppServer 		= Get-FarmServerName $SourceURL
    $Credential 	= Get-FarmCredential $SourceURL
	$retval			= ""
	$scriptblock 	= `
	{
		Param($SourceURL)
		
		try
		{
			Add-PSSnapin Microsoft.Sharepoint.Powershell
			Set-SPSite -Identity $SourceURL -LockState ReadOnly
	        if ( -not $?) 
	        { 
	          return "Could not set the site '$SourceURL' to ReadOnly."
	        }
		}
		catch [Exception]
		{
			return $_.Exception.Message
		}
		return $true
	}
	
	try 
	{
		$retval = Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $AppServer -ArgumentList $SourceURL -Authentication Credssp	
	    if($retval -eq $true)
	    {
	        Write-Host 'Made Site ReadOnly for ' $SourceURL
	        return $true
	    }
	}
	catch [Exception]
	{
		$retval = $_.Exception.Message
	}
	
	Write-Error $retval
	if($global:Workitem -ne $null)
    {
        $global:Workitem.Auto_Notes = $retval
    }
	return $false
}

Function Verify-SiteReadOnly
{
    Param([parameter(Mandatory = $true)] [string] $SourceURL)
		
    $AppServer		= Get-FarmServerName $SourceURL
    $Credential		= Get-FarmCredential $SourceURL
	$processid 		= [System.Diagnostics.Process]::GetCurrentProcess().id
	$retval			= ""
	$scriptblock 	= `
	{
		Param($SourceURL)
		try
		{
			Add-PSSnapin Microsoft.Sharepoint.Powershell 
			$siteCol = Get-SPSite -Identity $SourceURL
			if($siteCol -ne $null)
			{
				return $siteCol.ReadOnly
			}
		}
		catch [Exception]
		{
			return $_.Exception.Message
		}
		return "The Site '$SourceURL' is not available to verify its readonly state."
    }
	
	try
	{
		$retval		= Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $AppServer -ArgumentList $SourceURL -Authentication Credssp
		if($retval -eq $true)
	    {
	        Write-Host 'Verified site is in ReadOnly state and Updating the Database: WorkItemState to ReadOnly for '$SourceURL
	        Execute-UpdateWorkItemState -WorkitemState 'ReadOnly' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessEnded $(Get-Date)
			return $true
	    }
	}
	catch [Exception]
	{
		$retval = $_.Exception.Message
	}
	
	Write-Error $retval
	if($global:Workitem -ne $null)
    {
        $global:Workitem.Auto_Notes = $retval
    }
    return $false
}

Function Unlock-Site
{
    Param([parameter(Mandatory = $true)] [string] $SourceURL)
	
    Write-Host 'Unlocking Site for '$SourceURL
    $AppServer 		= Get-FarmServerName $SourceURL
    $Credential 	= Get-FarmCredential $SourceURL
	$retval			= ""
    $scriptblock 	= `
	{                     
	    Param($SourceURL)
		try
		{
	    	Add-PSSnapin Microsoft.Sharepoint.Powershell 
	    	Set-SPSite -Identity $SourceURL -LockState Unlock
	        if ( -not $?)
	        { 
	          return "Could not unlock the site '$SourceURL'."
	        }
		}
		catch [Exception]
		{
			return $_.Exception.Message
		}
		return $true
	}
	
	try
	{
	    Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $AppServer -ArgumentList $SourceURL -Authentication Credssp
		if($retval -eq $true)
		{
	    	Write-Host 'Unlocked Site for ' $SourceURL
			return $true
		}
	}
	catch [Exception]
	{
		$retval = $_.Exception.Message
	}
	
	Write-Error $retval
	if($global:Workitem -ne $null)
    {
        $global:Workitem.Auto_Notes = $retval
    }
    return $false
}

Function Verify-SiteUnlocked
{
 Param([parameter(Mandatory = $true)] [string] $SourceURL)
    
    $Credential 	= Get-FarmCredential $SourceURL
    $AppServer 		= Get-FarmServerName $SourceURL
	$retval			= ""
    $scriptblock 	= `
	{
		Param($SourceURL)
		try
		{
			Add-PSSnapin Microsoft.Sharepoint.Powershell 
			
			$siteCol = Get-SPSite -Identity $SourceURL
			if($siteCol -ne $null)
			{
				return !($siteCol.ReadOnly)
			}
		}
		catch [Exception]
		{
			return $_.Exception.Message
		}
		return "The Site '$SourceURL' is not available to verify its readonly state."
	}
	
	try
	{
    	$retval = Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $AppServer -ArgumentList $SourceURL -Authentication Credssp
	    if($retval -eq $true)
	    {
	        Write-Host 'Verified site is in Unlocked state and Updating the Database: WorkItemState to Unlocked for '$SourceURL
			return $true
	    }
	}
	catch [Exception]
	{
		$retval = $_.Exception.Message
	}
	
    Write-Error $retval
	if($global:Workitem -ne $null)
    {
        $global:Workitem.Auto_Notes = $retval
    }
    return $false
}

Function Export-Site
{
    Param([parameter(Mandatory = $true)][string] $SourceURL)

	Write-Host 'Exporting Site for '$SourceURL
	
    $Credential 	= Get-FarmCredential $SourceURL
    $processid 		= [System.Diagnostics.Process]::GetCurrentProcess().id
    $MyServer 		= $env:COMPUTERNAME
    $title 			= $SourceURL.Split("/")[-1] 
    $AppServer 		= Get-FarmServerName $SourceURL
	$retval			= ""
    $scriptblock 	= `
	{
		try
		{
			Param($SourceURL, $script, $MyServer, $title)
			
			Add-PSSnapin Microsoft.Sharepoint.Powershell 
			$sb = [scriptblock]::Create($script)
			. $sb                      
			# TODO: Need to replace Export-SPSite and return a value:
			Export-SPSite -Identity $SourceURL -Path //$MyServer/E$/sptMigration/sites/$title
	        if ( -not $?)
	        { 
	          	return "Could not export the site '$SourceURL'."
	        }
			return $true
		}
		catch [Exception]
		{
			return $_.Exception.Message
		}
	}
	
	try
	{
	    $script = (Get-Content '.\MigrationTools v1.7\MigrationCommands.ps1') -join "`r`n"
	    $retval = Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -Authentication Credssp -ComputerName $AppServer -ArgumentList $SourceURL, $script, $MyServer, $title
	    if(Test-Path //$MyServer/E$/sptMigration/sites/$title -and $retval -eq $true) # TODO: Need a better way of validating.
	    {
	        return $true
	    }
	}
	catch [Exception]
	{
		$retval = $_.Exception.Message
	}
	
    Write-Error $retval
	if($global:Workitem -ne $null)
    {
        $global:Workitem.Auto_Notes = $retval
    }
    return $false
}

Function Verify-ExportSite
{
	Param([parameter(Mandatory=$true)][string] $SourceURL)
	
	Write-Host 'Verifying Export Site for '$SourceURL
	
	$Credential 	= Get-FarmCredential $SourceURL
	$processid 		= [System.Diagnostics.Process]::GetCurrentProcess().id
	$start 			= date
	$AppServer 		= Get-FarmServerName $SourceURL
	$retval			= ""
	$scriptblock 	= `
	{
		Param($SourceURL)
		
		try
		{
			$path = 'E:\sptMigration\Sites\'+$SourceURL.Split("/")[-1]
			if(Test-Path -Path $path)
			{
			    if(((Get-Content $path'\export.log')[-1]).Split(" ")[-2] -eq 0)
			    {
			        return $true
			    }
			}
		}
		catch [Exception]
		{}
		return "Could not find the export.log in '$path'"
	}
	
	try
	{
		$retval = Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $env:COMPUTERNAME -ArgumentList $SourceURL -Authentication Credssp
		if($retval -eq $true)
		{
		    Write-Host 'Verified the export as Success and Updating the database: WorkItemState as Exported for '$SourceURL
		    Execute-UpdateWorkItemState -WorkitemState 'Exported' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start -ProcessEnded $(Get-Date)
		    return $true
		}
	}
	catch [Exception]
	{
		$retval = $_.Exception.Message
	}
	
    Write-Error $retval
	if($global:Workitem -ne $null)
    {
        $global:Workitem.Auto_Notes = $retval
    }
    return $false
}

Function Transform-Package
{
    Param([parameter(Mandatory = $true)][string] $SourceURL)
    
	Write-Host 'Transforming package for '$SourceURL
	
    $TargetURL 					= 'https://microsoft.sharepoint.com/teams/migrationdemo'
    $TransformationCredential 	= Get-TransformationCredential
    $start 						= date
	$Path 						= 'E:\sptMigration\Sites\' + $SourceURL.Split("/")[-1]
    $Foldername 				= 'E:\sptMigration\Sites\' + $SourceURL.Split("/")[-1]+'_xml'
	
    try
    {
	    New-Item -ItemType Directory -Path $Foldername
	    Copy-Item $Path'\*.xml' $Foldername
	    New-Item -ItemType Directory -Path $Path'\Data'
	    Copy-Item $Path'\*.xml' $Path'\Data'
	    Add-PSSnapin CDMMigrationCmdlets
		
       	Write-Host 'Starting keimos tool'
        Resolve-SPORemoteUsersFromData -TargetSiteCollectionURL $TargetURL -Credentials $TransformationCredential -DirectoryName $Path'\Data' -UserMappingFile E:\sptMigration\scripts\MasterCSV\UserMapping.csv -JobName ResolveUsers
        if ( -not $?) 
        { 
          Write-error "Exception while running Kimos Tool"
          return $false 
        }
		if(Test-Path $Path'\Data\UserGroupBackup.xml')
	    {
	        if((Get-Item $Path'\Data\UserGroup.xml').LastWriteTime -gt (Get-Item $Path'\Data\UserGroupBackup.xml').LastWriteTime)
	        {
	            #TODO Check whether UserNames are resolved to true and false
	            Write-Host 'Running PrimeEditor'
	            Set-ExecutionPolicy Bypass
	            Copy-Item '.\MigrationTools v1.7\PrimeEditor.ps1' $Path'\Data'
	            $location = Get-Location 
	            cd $Path'\Data' 
	            .\primeeditor.ps1 
	            cd $location 
	            if((Test-Path $Path'\Data\Data') -and (Test-Path $Path'\Data\Original'))
	            {
				    $processid = [System.Diagnostics.Process]::GetCurrentProcess().id

	                Copy-Item $Path'\Data\Data\*.xml' $Path
	                Remove-Item -Path $Path'\Data' -Recurse
	                Write-Host 'Updating the database: WorkItemState as Transformed for '$SourceURL
	                Execute-UpdateWorkItemState -WorkitemState 'Transformed' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start -ProcessEnded $(Get-Date)
	                return $true
	            }
	            Write-error "Resolved users and failed at PrimeEditor"
	            return $false
	        }
	    }
		$retval = "Failed to resolve users for the site '$SourceURL'"
    }
    catch [Exception]
    {
        $retval = $_.Exception.Message
    }

    Write-Error $retval
	if($global:Workitem -ne $null)
    {
        $global:Workitem.Auto_Notes = $retval
    }
    return $false
}

Function Verify-TransformPackage
{
	Param ([parameter(Mandatory = $true)][string] $SourceURL)
	
    $WorkItems 	= Read-CurrentWorkItems
    $WorkItem 	= $WorkItems.Tables[0]| where {$_.SourceUrl -eq $SourceURL}
    if($WorkItem -ne $null)
    {
        #if($WorkItem.
    }
}

Function Create-HashFile
{
    Param
    (
        [parameter(Mandatory=$true)]
        [string] $Path
    )
    $hash = dir $Path -Recurse | Where-Object {!$_.psiscontainer } | Get-FileHash
    $Tempxml =New-Object xml
    Export-CliXML -InputObject ($Tempxml, $hash) -Path $Path'\hash.xml'
    if(Test-Path $Path'\hash.xml')
    {
        return $true
    }
    else
    {
        return $false
    }
}
Function Get-FileHash
{
    Param
    (
        $Path,
        [ValidateSet("MD5", "SHA1", "SHA256", "SHA384", "SHA512")]
        $HashAlgorithm = "MD5"
    )

Set-StrictMode -Version Latest
## Create the hash object that calculates the hash of our file.
$hashType = [Type] "System.Security.Cryptography.$HashAlgorithm"
$hasher = $hashType::Create()
## Create an array to hold the list of files
$files = @()
## If they specified the file name as a parameter, add that to the list
## of files to process
if($path)
{
    $files += $path
}
## Otherwise, take the files that they piped in to the script.
## For each input file, put its full name into the file list
else
{

    $files += @($input | Foreach-Object { $_.FullName })
}
## Go through each of the items in the list of input files
foreach($file in $files)
{
    ## Skip the item if it is not a file
    if(-not (Test-Path $file -Type Leaf)) { continue }
    ## Convert it to a fully-qualified path
    $filename = (Resolve-Path $file).Path
    ## Use the ComputeHash method from the hash object to calculate
    ## the hash
    $inputStream = New-Object IO.StreamReader $filename
    $hashBytes = $hasher.ComputeHash($inputStream.BaseStream)
    $inputStream.Close()
    ## Convert the result to hexadecimal
    $builder = New-Object System.Text.StringBuilder
    $hashBytes | Foreach-Object { [void] $builder.Append($_.ToString("X2")) }
    ## Return a custom object with the important details from the
    ## hashing
    $output = New-Object PsObject -Property @{
        #Path = ([IO.Path]::GetFullPath($file));
        Path = ([IO.Path]::GetFileName($file));
        HashAlgorithm = $hashAlgorithm;
        HashValue = $builder.ToString()
    }
    $output
}
}
Function Upload-Package
{
    Param
    (
        [parameter(Mandatory=$true)]
        [string] $SourceURL,
        
        [parameter(Mandatory=$false)]
        [int] $WorkitemId
    )
    Write-Host 'Starting the Upload Package for '$SourceURL
    $start=date
    $processid=[System.Diagnostics.Process]::GetCurrentProcess().id
    $Azure=Get-AzureCredential $SourceURL
    #$title=$SourceURL.Split("/")[-1] 
    if($WorkitemId -ne $null)
    {
        $Url='http://'+$Azure.StorageAccount+'/'+$WorkitemId
    }
    else
    {
        $Url='http://'+$Azure.StorageAccount+'/'+($SourceURL.Split("/")[-1]).ToLower()
    }
    $Path='E:\sptMigration\Sites\'+$SourceURL.Split("/")[-1]
    $PrimaryAccessKey=$Azure.PrimaryAccessKey
    $Location=Get-Location
    Cd E:\sptMigration\scripts\AZCopy
    try
    {
        $results= .\AzCopy.exe $("""$Path""") $("""$Url""") $("/destKey:$PrimaryAccessKey") '/S' 
        if ( -not $?)
        {
          Write-Host 'Exception while uploading files to Azure'
          cd $Location
          return $false
        }
        else
        {
            if(([int] ($results[3].Split(":")[1]) -eq [int] ($results[4].Split(":")[1])) -and ([int] ($results[5].Split(":")[1]) -eq 0))
            {
                cd $Location
                $end=date
                Write-Host 'Updating Database WorkitemState to Uploaded for '$SourceURL
                Execute-UpdateWorkItemState -WorkitemState 'Uploaded' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start -ProcessEnded $end
                return $true
            }
            else
            {
                Write-Host 'Uploading files to Azure unsuccessful'
                cd $Location
                $results
                return $false
            }
        }
    }
    catch [Exception]
    {
        write-host $_.Exception.Message -ForegroundColor Red
        cd $Location
        return $false
    }
}
Function Download-Package
{
    Param
    (
        [parameter(Mandatory=$true)]
        [string] $SourceURL,

        [parameter(Mandatory=$false)]
        [int] $WorkitemId 
    )
    $start=date
    #$title=$SourceURL.Split("/")[-1] 
    Write-Host 'Downloading package for '$SourceURL
    $Azure=Get-AzureCredential $SourceURL
    if($WorkitemId -ne $null)
    {
        $Url='http://'+$Azure.StorageAccount+'/'+$WorkitemId
    }
    else
    {
        $Url='http://'+$Azure.StorageAccount+'/'+($SourceURL.Split("/")[-1]).ToLower()
    }
    if(($SourceURL.Split("/")[2]).ToLower() -eq 'sharepoint')
    {
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\NA\'+ $SourceURL.Split("/")[-1] 
    }
    elseif(($SourceURL.Split("/")[2]).ToLower() -eq 'team')
    {
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\Team\'+ $SourceURL.Split("/")[-1] 
    }
    elseif(($SourceURL.Split("/")[2]).ToLower() -eq 'sharepointemea')
    {
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\EMEA\'+ $SourceURL.Split("/")[-1] 
    }
    elseif(($SourceURL.Split("/")[2]).ToLower() -eq 'sharepointasia')
    {
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\APAC\'+ $SourceURL.Split("/")[-1] 
    }
    #$Path= 'D:\sptMigration\Sites\'+$SourceURL.Split("/")[-1] 
    $PrimaryAccessKey=$Azure.PrimaryAccessKey
    Write-Host 'Downloading the package to the folder '$Path
    $Location=Get-Location
    Cd D:/AZCopy
    try
    {
        $results= .\AzCopy.exe $("""$Url""") $("""$Path""") $("/sourceKey:$PrimaryAccessKey") '/S' 
        if ( -not $?)
        {
          Write-Host 'Exception while downloading files from Azure' -ForegroundColor Red
          $results
          Cd $Location
          return $false
        }
        else
        {
            if(([int] ($results[3].Split(":")[1]) -eq [int] ($results[4].Split(":")[1])) -and ([int] ($results[5].Split(":")[1]) -eq 0))
            {
                $results
                Cd $Location
                Write-Host 'Verified the Download is successfull and Updating the database WorkItemState to Downloaded'
                $end=date
                Execute-UpdateWorkItemState -WorkitemState 'Downloaded' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start -ProcessEnded $end      
                return $true
            }
            else
            {
                Write-Host 'Downloading files from Azure unsuccessful' -ForegroundColor Red
                $results
                Cd $Location
                return $false
            }
        }
    }
    catch [Exception]
    {
        write-host $_.Exception.Message -ForegroundColor Red
        cd $Location
        return
    }
}
Function Verify-Download
{
    Param
    (
        [parameter(Mandatory=$true)]
        [string] $SourceURL
    )
    $start=date
    $processid=[System.Diagnostics.Process]::GetCurrentProcess().id
    $Path= 'D:\sptMigration\Sites\'+$SourceURL.Split("/")[-1] 
    if(Test-Path $Path)
    {
        $OriginalHash = Import-Clixml $Path'\hash.xml'
        $CurrentHash= dir $Path -Recurse | Where-Object {!$_.psiscontainer } | Get-FileHash
        $exceptions = 
                     foreach($orig in $OriginalHash[1])
                     {
                        $origfound = $false;
                        $hashsame = $false;
                        foreach($current in $currenthash)
                        {
                            if ($current.Path -eq $orig.Path) 
                            {
                                $origfound = $true;
                                if ($current.HashValue -eq $orig.HashValue)
                                {
                                    $hashsame = $true;                                    
                                }
                                break;
                            }
                        }
                        if (-not $origfound -or -not $hashsame) 
                        {
                            $orig
                        }
                     }
      if(!$exceptions)
      {
        Write-Host 'Verified the Download is successfull and Updating the database WorkItemState to Downloaded'
        $end=date
        Execute-UpdateWorkItemState -WorkitemState 'Downloaded' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start -ProcessEnded $end
      }
      else
      {
        Write-Host 'Download Failed: Following files are not downloaded or their hashvalues not matched' -ForegroundColor Red
        $exceptions
      }
    }
    else
    {
        Write-Host 'Download Failed: Folder does not exists at '$Path -ForegroundColor Red
    }
}
Function Import-TransformedSite
{
    Param
    (
        [parameter(Mandatory=$true)]
        [string] $SourceURL,

        [parameter(Mandatory=$true)]
        [string] $TargetURL
    )
    
    Add-PSSnapin Microsoft.Sharepoint.Powershell
    . './MigrationTools v1.7/MigrationCommands.ps1'
    Write-Host 'Importing site for '$TargetURL
    if(($SourceURL.Split("/")[2]).ToLower() -eq 'sharepoint')
    {
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\NA\'+ $SourceURL.Split("/")[-1] 
    }
    elseif(($SourceURL.Split("/")[2]).ToLower() -eq 'team')
    {
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\Team\'+ $SourceURL.Split("/")[-1] 
    }
    elseif(($SourceURL.Split("/")[2]).ToLower() -eq 'sharepointemea')
    {
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\EMEA\'+ $SourceURL.Split("/")[-1] 
    }
    elseif(($SourceURL.Split("/")[2]).ToLower() -eq 'sharepointasia')
    {
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\APAC\'+ $SourceURL.Split("/")[-1] 
    }
    #$Path= 'D:\sptMigration\Sites\'+$TargetURL.Split("/")[-1]     
    try
    {
        Import-SPSite –Identity $TargetURL -Path $Path
        Import-SPSiteAdministrators -Identity $TargetURL -Path $Path
    }
    catch [Exception]
    {
        write-host $_.Exception.Message -ForegroundColor Red
        return $false
    }
}
Function Verify-ImportSite
{
Param
(
    [parameter(Mandatory=$true)]
    [string] $SourceURL,

    [parameter(Mandatory=$true)]
    [string] $TargetURL
)
$Credential=Get-FarmCredential $SourceURL
$processid=[System.Diagnostics.Process]::GetCurrentProcess().id
$start=date
Write-Host 'Verifying Import Site for '$TargetURL
#$path='D:\sptMigration\Sites\'+$TargetURL.Split("/")[-1]
if(($SourceURL.Split("/")[2]).ToLower() -eq 'sharepoint')
{
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\NA\'+ $SourceURL.Split("/")[-1] 
    }
elseif(($SourceURL.Split("/")[2]).ToLower() -eq 'team')
{
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\Team\'+ $SourceURL.Split("/")[-1] 
    }
elseif(($SourceURL.Split("/")[2]).ToLower() -eq 'sharepointemea')
{
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\EMEA\'+ $SourceURL.Split("/")[-1] 
    }
elseif(($SourceURL.Split("/")[2]).ToLower() -eq 'sharepointasia')
{
        $Path='\\Ch1yl1dpm030\v$\MSIT-COLLAB-MIGRATION\APAC\'+ $SourceURL.Split("/")[-1] 
    }
if(Test-Path -Path $Path)
{
    if(((Get-Content $Path'\import.log')[-1]).Split(" ")[-2] -eq 0)
    {
        Write-Host 'No errors found in the import.log Updating database WorkitemState to Imported'
        $end=date
        Execute-UpdateWorkItemState -WorkitemState 'Imported' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start -ProcessEnded $end
        return $true
    }
    else
    { 
        Write-Host 'Errors found in the import log' -ForegroundColor Red
        return $false 
    }
}
else
{ 
    Write-Host 'Cannot find the folder '$Path -ForegroundColor Red
    return $false 
}

}
Function Import-Workflows
{
    metavis -cmd copyworkflows -srcsite http://host/site -srcuser account -srcepass password -trgtsite http://host/site2 -trgtuser  account -trgtepass password -includesubsites -includelists
}
Function Upgrade-MigratedSite
{
    Param
    (        
        [parameter(Mandatory=$true)]
        [string] $TargetURL
    )
    if (-not(Get-PSSnapin | where { $_.name -eq "Microsoft.SharePoint.PowerShell" }))
    {  
	    Add-PSSnapin Microsoft.Sharepoint.Powershell 
    }
    #Add-PSSnapin Microsoft.Sharepoint.Powershell
    Upgrade-SPSite -Identity $TargetURL.TrimEnd(' ') -VersionUpgrade -Unthrottled
}
Function Execute-ExportModule
{
Param
(
    [parameter(Mandatory=$true)]
    [string] $SourceURL
)
$host.ui.RawUI.WindowTitle = 'Export - '+$SourceURL.Split("/")[-1] 
if(Set-SiteReadOnly -SourceURL $SourceURL)
{
    if(Verify-SiteReadOnly -SourceURL $SourceURL)
    {
        if(Export-Site -SourceURL $SourceURL)
        {
            Verify-ExportSite -SourceURL $SourceURL
        }
        else
        {
            Write-Host 'Error while exporting Site '$SourceURL -ForegroundColor Red
        }
    }
    else
    {
        Write-Host 'Site is not set to ReadOnly' -ForegroundColor Red
    }
}
else
{
    Write-Host 'Error while making Site ReadOnly for '$SourceURL -ForegroundColor Red
}
}
Function Execute-TransformModule
{
    Param
    (
        [parameter(Mandatory=$true)]
        [string] $SourceURL
    )
    $Path='E:\sptMigration\Sites\'+$SourceURL.Split("/")[-1] 
    $host.ui.RawUI.WindowTitle = 'TRANSFORM and UPLOAD- '+$SourceURL.Split("/")[-1]  
    if(Transform-Package -SourceURL $SourceURL)
    {
        #Removed the Hashvalue check logic so removing this to create hash file as it is not going to be used.
        #if(Create-HashFile -Path $Path)
        #{
        $WorkItems = Read-CurrentWorkItems
        $WorkItem=$WorkItems.Tables[0]| where {$_.SourceUrl -eq $SourceURL}
        if($WorkItem -ne $null)
        {
            if($WorkItem.WorkitemState -eq 'Transformed')
            {   
                $WorkitemId=$WorkItem.WorkitemId
                Upload-Package -SourceURL $SourceURL -WorkitemId $WorkitemId
            }
            else
            {
                Write-Host 'Database is not updated to Transformed so Package is not uploaded for '$SourceURL -ForegroundColor Red
            }
        }        
        else
        {
            Write-Host 'WorkItem Not Found' -ForegroundColor Red
        }
        #}
    }
    else
    {
        Write-Host 'Transformation failed' -ForegroundColor Red
    }
}
Function Execute-DownloadModule
{
    Param
    (
        [parameter(Mandatory=$true)]
        [string] $SourceURL
    )
    $host.ui.RawUI.WindowTitle = 'Download and Import - '+$SourceURL.Split("/")[-1]  
    $WorkItems = Read-CurrentWorkItems
    $WorkItem=$WorkItems.Tables[0]| where {$_.SourceUrl -eq $SourceURL}
    if($WorkItem -ne $null)
    {
        $TargetURL=$WorkItem.TargetURL
        $WorkitemId=$WorkItem.WorkitemId
        if(Download-Package -SourceURL $SourceURL -WorkitemId $WorkitemId)
        {
        #Removed the hashvalue check as it is taking long time to verify. Need to revisit this in future
        #if(Verify-Download -SourceURL $SourceURL)
        #{  
            if(Import-TransformedSite -SourceURL $SourceURL -TargetURL $TargetURL)
            {
                Verify-ImportSite -SourceURL $SourceURL -TargetURL $TargetURL
            }
            else
            {
                Write-Host 'Import Failed' -ForegroundColor Red
            }
            
        #}
        }
        else
        {
            Write-Host 'Download Failed' -ForegroundColor Red
        }
    }
    else
    {
        Write-Host 'WorkItem Not Found' -ForegroundColor Red
    }
}
