
function check-RequestedRollback
{
    param([parameter(Mandatory = $true)] [System.Data.DataRow] $Workitem )
    
    return $false
}

function Execute-CompleteSiteRollback
{
    [cmdletbinding()]
    Param
    (   [parameter(Mandatory = $true)] [string] $SourceURL,
        [parameter(Mandatory = $false)] [string] $Auto_Notes)

    $SqlConnection 			= New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = Get-MigrationCoordinatorConnectionString
    $SqlConnection.Open()

    $SqlCmd 				= New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection 		= $SqlConnection
    $SqlCmd.CommandText 	= "EXECUTION_CompleteSiteRollback"
    $SqlCmd.Parameters.Add("@SourceSiteURL", $SourceURL) | Out-Null

    $SqlCmd.Parameters.Add("@FinalEmailSendDateUTC", $(Get-Date).ToUniversalTime()) | Out-Null
    if ($PSBoundParameters.ContainsKey("Auto_Notes"))
    {
        $SqlCmd.Parameters.Add("@Notes", $Auto_Notes) | Out-Null
    }

    $SqlCmd.CommandTimeout 	= 0
    $SqlCmd.CommandType 	= [System.Data.CommandType]::StoredProcedure;          
    $SqlCmd.ExecuteNonQuery() | Out-Null
              
    $SqlConnection.Close();
    return $true # TODO: return a failure if there is one
}

function Execute-InitiateRequestedSiteRollback
{
    [cmdletbinding()]
    Param ([parameter(Mandatory = $true)] [string] $SourceSiteURL)

    $SqlConnection 			= New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = Get-MigrationCoordinatorConnectionString
    $SqlConnection.Open()

    $SqlCmd 				= New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection 		= $SqlConnection
    $SqlCmd.CommandText 	= "EXECUTION_InitiateRequestedSiteRollback"
    $SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null
    $SqlCmd.CommandTimeout 	= 0
    $SqlCmd.CommandType 	= [System.Data.CommandType]::StoredProcedure;          
    $SqlCmd.ExecuteNonQuery() | Out-Null
              
    $SqlConnection.Close();
    return $true # TODO: return a failure if there is one
}

Function Execute-SiteRollback
{
    Param (	[parameter(Mandatory = $true)] [string] $SourceURL,
			[Parameter(Position = 0)] [ValidateSet('UserRequested','ExecutionDelayed')][System.String]$Reason)

 	if($(Read-MigrationAutomationConfiguration) -eq $false)
    {
		return
	}

    $uri1 				= $SourceURL -as [System.URI] # Cause an exception if it is not a URL
    if($uri1.LocalPath -eq $null)
    {
        Write-Error ("The url " + $SourceURL + " is not a valid subsite.") -Category InvalidArgument
        return
    }
    $FarmUrl_cleaned 	= $uri1.Scheme + "://" + $uri1.Host

    write-host "Reverting" $uri1.AbsoluteUri "to its pre-migraton state"

    # TODO: It would be better to just get the state of one URL, but this works for now:
    $WorkItems 			= Read-CurrentWorkItems -FarmUrl $FarmUrl_cleaned
    $global:Workitem 	= $WorkItems.Tables[0] | ? {$_.SourceURL -eq $uri1.AbsoluteUri}
	$RetryCount 		= 0
	$UTCStartTime 		= $(Get-Date).ToUniversalTime()
		
    if($global:Workitem -eq $null)
    {
		if($Reason -eq "UserRequested")
		{
			# We need to make a new 'RequestedSiteRollback' workitem for this site:
		    if($(Execute-InitiateRequestedSiteRollback $uri1.AbsoluteUri) -eq $false)
		    {
		        return
		    }
			$WorkItems 			= Read-CurrentWorkItems -FarmUrl $FarmUrl_cleaned
			$global:Workitem 	= $WorkItems.Tables[0] | ? {$_.SourceURL -eq $uri1.AbsoluteUri}
			if($global:Workitem -eq $null)
    		{
				Write-Error "Could not create a workitem for $uri1.AbsoluteUri"
				return
			}
		}
		else
		{
			Write-Error "There isn't an existing workitem for $uri1.AbsoluteUri"
			return
		}
    }
	else
	{
		if($Reason -eq "UserRequested")
		{
			if($global:Workitem.WorkItemTypeName -ne "Requested Rollback")
			{
		        Write-Error ("The workitem is active and is not a requested rollback.  It must complete migration prior to rolling it back.") -Category InvalidArgument
			    return $global:Workitem
			}
			# TODO: The retry count only works properly for a requested rollback, as it's a new workitem.  Need another method for other workitems:
			if($global:Workitem.WorkitemState -ne "RequiresRedirectRemoval")
			{
				$RetryCount = $global:Workitem.RetryCount + 1
			}
		}
		if($global:Workitem.WorkitemState -eq "RequiresRequestedRollbackDeletion" -or $global:Workitem.WorkitemState -eq "RequiresTargetSiteDeletionForExecutionDelayedDescheduling")
		{
			Write-Host "You do not need to run 'Execute-RequestedSiteRollback'."
			Write-Host "The workitem currently needs the site to be deleted."
			Write-Host "The next step is to execute 'Remove-SiteUsingTenateAdminCreds'."
			return
		}
	}

	$global:Workitem.Table.Columns.Add("Auto_Notes", [string]) | Out-Null # Add Notes to the status so they can be passed to status updates.
    
    $ProcessStartedUTC = $(Get-Date).ToUniversalTime()

    if($(Execute-UpdateWorkItemState -WorkitemState "RemovingRedirect" -SourceSiteURL $uri1.AbsoluteUri -ProcessingServer $env:COMPUTERNAME -ProcessStarted $ProcessStartedUTC) -eq $false)
    {
        return
    }
    if($(Unlock-Site $uri1.AbsoluteUri) -eq $false)
    {
        return
    }
    if($(Verify-SiteUnlocked $uri1.AbsoluteUri) -eq $false)
    {
        return
    }
    if($(Disable-Redirect $uri1.AbsoluteUri) -eq $false)
    {
        return
    }
	$FoundSite = $false
	Write-Host "Waiting for 1 minute or more for $SourceURL to become available." -NoNewline
	Sleep -Seconds 2 # Sleeping a moment to better help the first try work:
    For ( $x = 0; $x -lt 10; $x++)
	{
		Write-Host "." -NoNewline
		if($(Verify-UrlIsRedirected -SourceURL $uri1.AbsoluteUri -ReverseResult "true") -eq $true)
	    {
			$FoundSite = $true
	        break
	    }
		Sleep -Seconds 6
	}
	if($FoundSite -eq $false)
	{
		# Execute-UpdateWorkItemState -SourceSiteURL $SourceURL -WorkitemState "RequiresAssistance" -ProcessingServer $env:COMPUTERNAME -ProcessStarted $ProcessStartedUTC -ProcessEnded $($(Get-Date).ToUniversalTime()) -RetryCount $RetryCount -Notes "The redirect still appears to be in place."
		Write-Error "The redirect appears to still be in place."
		Write-Host "The workitem state was NOT set to 'RequiresAssistance' as you are actively working on this workitem!"
		return
	}
	Write-Host "`n`n$SourceURL Is ready to use.  An email will be sent to the owners later"

	$SPOTenateAdminCreds = Get-TenateAdminCreds $global:Workitem.TargetURL
	if($SPOTenateAdminCreds -ne $null)
	{
		if($(Remove-SiteAsTenateAdmin -TargetURL $global:Workitem.TargetURL -Reason $Reason) -eq $false)
		{
			# Execute-UpdateWorkItemState -SourceSiteURL $SourceURL -WorkitemState "RequiresAssistance" -ProcessingServer $env:COMPUTERNAME -ProcessStarted $ProcessStartedUTC -ProcessEnded $($(Get-Date).ToUniversalTime()) -RetryCount $RetryCount -Notes $global:Workitem.Auto_Notes
			# Will happen if the user intended to run this, but permissions (access) failed. 
			Write-Host "Run 'Execute-UpdateWorkItemState' independently, or manually set the workitem state to,"
			Write-Host "'RequiresRequestedRollbackDeletion' and let the automation execute the final steps."
			Write-Host "The state was NOT set to 'RequiresAssistance' as you are actively working on this workitem!`n"
		}
		return
	}
	if($Reason -eq "UserRequested")
	{
		Execute-UpdateWorkItemState -SourceSiteURL $uri1.AbsoluteUri -WorkitemState "RequiresRequestedRollbackDeletion" -ProcessingServer $env:COMPUTERNAME -ProcessStarted $ProcessStartedUTC -ProcessEnded $($(Get-Date).ToUniversalTime()) -RetryCount $RetryCount
	}
	else
	{
		Execute-UpdateWorkItemState -SourceSiteURL $uri1.AbsoluteUri -WorkitemState "RequiresTargetSiteDeletionForExecutionDelayedDescheduling" -ProcessingServer $env:COMPUTERNAME -ProcessStarted $ProcessStartedUTC -ProcessEnded $($(Get-Date).ToUniversalTime()) -RetryCount $RetryCount
	}

	write-host "The SPO site must be deleted before the comms will be sent."
	write-host "This should happen automatically, or run you can Remove-SiteUsingTenateAdminCreds after"
	Write-Host "using 'Set-TenateAdminCreds' - if you know them."
}

Function Remove-SiteAsTenateAdmin
{
	Param (	[parameter(Mandatory = $true)] [string] $TargetURL,
			[Parameter(Position = 0)] [ValidateSet('UserRequested','ExecutionDelayed')][System.String] $Reason)
 
 	if($(Read-MigrationAutomationConfiguration) -eq $false)
    {
		return $false
	}
	
	$uri1 				= $TargetURL -as [System.URI] # Cause an exception if it is not a URL

    if($uri1.LocalPath -eq $null)
    {
        Write-Error ("The url " + $TargetURL + " is not a valid subsite.") -Category InvalidArgument
        return $false
    }
	if($global:Workitem -ne $null)
	{
		if($global:Workitem.TargetURL -ne $uri1.AbsoluteUri)
		{
			 $global:Workitem = $null
		}
	}
	if($global:Workitem -eq $null)
	{
		$WorkItems 			= Read-CurrentWorkItems			# Read all the workitems, as we don't know the origional farm
	    $global:Workitem 	= $WorkItems.Tables[0] | ? {$_.TargetURL -eq $uri1.AbsoluteUri}
		if($global:Workitem -ne $null)
		{
			$global:Workitem.Table.Columns.Add("Auto_Notes", [string]) | Out-Null # Add Notes to the status so they can be passed to status updates.
		}
	}
	if($global:Workitem -eq $null)
	{
		$NotAValidSite 	= "No workitem was found for '$($uri1.AbsoluteUri)'."
		Write-Error $NotAValidSite
		return $false
	}
	if($global:Workitem.Count -gt 1)
	{
		$MultipleSites 	= "Several workitems were found for '$($uri1.AbsoluteUri)'."
		Write-Error $MultipleSites
		$global:Workitem
		return $false
	}

    # This is a way to delete a site if we have tenate admin access:
    if ((Get-Module Microsoft.Online.SharePoint.PowerShell).Count -eq 0)
    {
        Import-Module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking
    }
	$TenateAdminCreds 	= Get-TenateAdminCreds $uri1.AbsoluteUri
	if($TenateAdminCreds -eq $null)
	{
		$CredsError 	= "You must use 'Set-TenateAdminCreds' before running 'Remove-SiteAsTenateAdmin'."
		Write-Error $CredsError
		if($global:Workitem -ne $null)
		{
			$global:Workitem.Auto_Notes = $CredsError
		}
		return $false
	}

	$FarmUrl_cleaned 	= $uri1.Scheme + "://" + $uri1.Host
	$destination 		= $global:GlobalSettings.SelectSingleNode("Destination[@FarmName='$FarmUrl_cleaned']")
	try{
	    Connect-SPOService -Url $destination.TenantSite.Name -Credential $TenateAdminCreds
		Remove-SPOSite -Identity $uri1.AbsoluteUri -Confirm:$false -NoWait
		Remove-SPODeletedSite -Identity $uri1.AbsoluteUri -Confirm:$false
		Disconnect-SPOService
		
		if($Reason -eq 'UserRequested')
		{
			Execute-UpdateWorkItemState -SourceSiteURL $global:Workitem.SourceURL -WorkitemState "RequiresMigrationRollbackComms" -ProcessingServer $env:COMPUTERNAME -ProcessStarted $ProcessStartedUTC -ProcessEnded $($(Get-Date).ToUniversalTime()) -RetryCount $RetryCount
			Write-Host "The workitem state has been changed to 'RequiresMigrationRollbackComms'."
		}
		elseif ($Reason -eq 'ExecutionDelayed')
		{
			Execute-UpdateWorkItemState -SourceSiteURL $global:Workitem.SourceURL -WorkitemState "RequiresMigrationExecutionDelayedComms" -ProcessingServer $env:COMPUTERNAME -ProcessStarted $ProcessStartedUTC -ProcessEnded $($(Get-Date).ToUniversalTime()) -RetryCount $RetryCount
			Write-Host "The workitem state has been changed to 'RequiresMigrationExecutionDelayedComms'."
		}
		return $true
	}
	catch [Exception]
	{
		Write-Error $_.Exception
	}
	return $false
}