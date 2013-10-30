function Set-WorkItemStateToNow
{
    Param
    (             
        [parameter(Mandatory = $true)] [string] $SourceURL,
        [parameter(Mandatory = $true)] [ValidateLength(0,64)] [string] $NextWorkitemState,
        [parameter(Mandatory = $false)] [int] $Auto_LastRetryCount,
        [parameter(Mandatory = $false)] [string] $InitialEmailWasJustSent,
        [parameter(Mandatory = $false)] [string] $Auto_Notes
    )
	if($Auto_LastRetryCount -eq $null)
	{
		$Auto_LastRetryCount = 0
	}
	# Set the state of the in-memory obect so that it's not picked up by other sequences:
	if($global:Workitem -ne $null)
	{
		$global:Workitem.WorkitemState = $NextWorkitemState # TODO: Do this with all functions that change the state.
	}
	
    $UTCTimeNow = $(Get-Date).ToUniversalTime()
	
    if ($PSBoundParameters.ContainsKey("InitialEmailWasJustSent"))
    {
        if($InitialEmailWasJustSent -eq "True")
        {
            if( $(Execute-UpdateWorkItem -SourceSiteURL $SourceURL -InitialCommsSendDateUTC $UTCTimeNow) -eq $true)
			{
				return $(Execute-UpdateWorkItemState -SourceSiteURL $SourceURL -WorkitemState $NextWorkitemState -ProcessingServer $env:COMPUTERNAME -ProcessEnded $UTCTimeNow -RetryCount $Auto_LastRetryCount)
			}
			return $false
        }
    }
    return $(Execute-UpdateWorkItemState -SourceSiteURL $SourceURL -WorkitemState $NextWorkitemState -ProcessingServer $env:COMPUTERNAME -ProcessEnded $UTCTimeNow -RetryCount $Auto_LastRetryCount -Notes $Auto_Notes)
#-ProcessId -ProcessStartedTime
}

function Set-MigrationCompleteToNow
{
    Param
    (             
        [parameter(Mandatory=$true)] [string] $SourceURL
    )
	# Set the state of the in-memory obect so that it's not picked up by other sequences:
	if($global:Workitem -ne $null)
	{
		$global:Workitem.WorkitemState = "Complete" # TODO: Do this with all functions that change the state.
	}
    $UTCTimeNow = $(Get-Date).ToUniversalTime()
    return Execute-CompleteSiteMigration -SourceSiteURL $SourceURL -FinalEmailSendDateUTC $UTCTimeNow
}

function Read-CurrentWorkItems
{
    param  ([parameter(Mandatory=$false)] [string] $FarmUrl,
            [parameter(Mandatory=$false)] [DateTime] $WorkDate)

    $RetDataset = new-object System.Data.Dataset
    
    trap [Exception] { 
       write-error $($_.Exception.Message);
       write-host ""
       return $RetDataset; 
    }
    
    $FarmUrl_cleaned = ""
    if($FarmUrl -ne "")
    {
        $FarmUri = $FarmUrl -as [System.URI]
        $FarmUrl_cleaned = $FarmUri.Scheme + "://" + $FarmUri.Host
    }

    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		Write-Host "    Reading from the Coordinator Database" $FarmUrl_cleaned "" -nonewline

        foreach($node in $global:AutomationNodesXML)
        {
            if($FarmUrl -ne "" -and $node.FarmName -ne $FarmUrl_cleaned)
            {
                continue
            }
            
            if($node.WebAppID -eq $null)
            {
                continue    # TODO: if a specific site is specified, return only rows for that site
            }

			$SqlConnection 								= New-Object System.Data.SqlClient.SqlConnection
			$SqlConnection.ConnectionString				= Get-MigrationCoordinatorConnectionString
            $SqlCmd 									= New-Object System.Data.SqlClient.SqlCommand
            $SqlCmd.CommandText 						= "EXECUTION_GetCurrentWorkItems"
            $SqlCmd.Connection 							= $SqlConnection
            $SqlCmd.CommandType 						= [System.Data.CommandType]::StoredProcedure
            $SqlCmd.Parameters.Add("WorkDate", [system.data.SqlDbType]::date) | out-Null
            $SqlCmd.Parameters.Add("WebAppId", [system.data.SqlDbType]::uniqueidentifier) | out-Null
            $SqlCmd.Parameters['WorkDate'].Direction 	= [system.data.ParameterDirection]::Input
            $SqlCmd.Parameters['WebAppId'].Direction 	= [system.data.ParameterDirection]::Input

            if($WorkDate -ne $null)
            {
                $SqlCmd.Parameters['WorkDate'].value    = $WorkDate  
            }
            else
            {
                $SqlCmd.Parameters['WorkDate'].value    = [DBNull]::Value
            }
            
            if($FarmUrl -ne $null)
            {
                $SqlCmd.Parameters['WebAppId'].value 	= New-object Guid($node.WebAppID)
            }
            else
            {
                $SqlCmd.Parameters['WebAppId'].value   = [DBNull]::Value
            }     
			
            $dataset = new-object System.Data.Dataset 
            $DataAdapter = new-object System.Data.SqlClient.SqlDataAdapter $SqlCmd
            $DataAdapter.Fill($dataset) | out-Null
            if($dataset.Tables.Count -gt 0)
            {
                $RetDataset.Merge($dataset) | out-Null
            }
        }
		Write-Host "completed.`n"
    }
    return $RetDataset
}


function Read-LatestScheduledRates
{
    $RetDataset = new-object System.Data.Dataset
    
    trap [Exception] { 
       write-error $($_.Exception.Message);
       write-host ""
       return $RetDataset.Tables
    }
    
    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		Write-Host "    Reading the Scheduled Rates " -nonewline

		$SqlConnection 								= New-Object System.Data.SqlClient.SqlConnection
		$SqlConnection.ConnectionString				= Get-MigrationCoordinatorConnectionString
        $SqlCmd 									= New-Object System.Data.SqlClient.SqlCommand
        $SqlCmd.CommandText 						= "REPORT_DailyWorkUnits"
        $SqlCmd.Connection 							= $SqlConnection
        $SqlCmd.CommandType 						= [System.Data.CommandType]::StoredProcedure
        $SqlCmd.Parameters.Add("StartDate", [system.data.SqlDbType]::date) | out-Null
        $SqlCmd.Parameters.Add("EndDate", [system.data.SqlDbType]::date) | out-Null
        $SqlCmd.Parameters['StartDate'].Direction 	= [system.data.ParameterDirection]::Input
        $SqlCmd.Parameters['EndDate'].Direction 	= [system.data.ParameterDirection]::Input
        $SqlCmd.Parameters['StartDate'].value   	= Get-Date
        $SqlCmd.Parameters['EndDate'].value			= $SqlCmd.Parameters['StartDate'].value
        $dataset = new-object System.Data.Dataset 
        $DataAdapter = new-object System.Data.SqlClient.SqlDataAdapter $SqlCmd
        $DataAdapter.Fill($dataset) | out-Null
        if($dataset.Tables.Count -gt 0)
        {
            $RetDataset.Merge($dataset) | out-Null
        }
		Write-Host "completed.`n"
    }
    return $RetDataset.Tables
}

function Set-DescheduleSiteMigrationToNow
{
    Param
    (             
        [parameter(Mandatory = $true)] [string] $SourceURL,
		[parameter(Mandatory = $false)] [string] $Auto_Notes,
		[parameter(Mandatory = $false)] [string] $RequestedDeschedule
    )

    $UTCTimeNow = $(Get-Date).ToUniversalTime()

	# True means it was requested by the user:
	if($RequestedDeschedule -eq "True")
	{
		return Execute-DescheduleSiteMigration -SourceSiteURL $SourceURL -FinalEmailSendDateUTC $UTCTimeNow -RequestedDeschedule $true -Notes $Auto_Notes
	}
	return Execute-DescheduleSiteMigration -SourceSiteURL $SourceURL -FinalEmailSendDateUTC $UTCTimeNow -RequestedDeschedule $false -Notes $Auto_Notes
}
