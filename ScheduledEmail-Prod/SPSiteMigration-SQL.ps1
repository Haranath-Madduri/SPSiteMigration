function Set-WorkItemStateToNow
{
    Param
    (             
        [parameter(Mandatory=$true)] [string] $SourceURL,
        [parameter(Mandatory=$true)] [ValidateLength(0,64)] [string] $NextWorkitemState,
        [parameter(Mandatory=$false)] [string] $InitialEmailWasJustSent
    )

    $UTCTimeNow = $(Get-Date).ToUniversalTime()
    if ($PSBoundParameters.ContainsKey("$InitialEmailWasJustSent"))
    {
        if($InitialEmailWasJustSent -eq "True")
        {
            Execute-UpdateWorkItemState -SourceURL $SourceURL -NewWorkitemState $NextWorkitemState -ProcessingServer $env:COMPUTERNAME -ProcessEndedTime $UTCTimeNow
            return
        }
    }
    Execute-UpdateWorkItemState -SourceURL $SourceURL -NewWorkitemState $NextWorkitemState -ProcessingServer $env:COMPUTERNAME -ProcessEndedTime $UTCTimeNow -InitialUTCCommsSendDateTime $UTCTimeNow
#-ProcessId -ProcessStartedTime -RetryCount -Notes 
}

function Set-MigrationCompleteToNow
{
    Param
    (             
        [parameter(Mandatory=$true)] [string] $SourceURL
    )

    $UTCTimeNow = $(Get-Date).ToUniversalTime()
    Execute-CompleteSiteMigration -SourceURL $SourceURL -FinalEmailSendDateUTC $UTCTimeNow
}

function Read-CurrentWorkItems
{
    param  ([parameter(Mandatory=$false)] [string] $FarmUrl,
            [parameter(Mandatory=$false)] [DateTime] $StartingDate)

    $RetDataset = new-object System.Data.Dataset
    
    trap [Exception] { 
       write-error $($_.Exception.Message);
       write-host ""
       return $RetDataset; 
    }
    
    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		Write-Host "    Reading from the Coordinator Database " -nonewline
        foreach($node in $global:AutomationNodesXML)
        {
            if($FarmUrl -ne "")
            {
                $FarmUri = $FarmUrl -as [System.URI]
                $FarmUrl_cleaned = $FarmUri.Scheme + "://" + $FarmUri.Host
                if($node.FarmName -ne $FarmUrl_cleaned)
                {
                    continue
                }
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

            if($StartingDate -ne $null)
            {
                $SqlCmd.Parameters['WorkDate'].value    = $StartingDate  
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
