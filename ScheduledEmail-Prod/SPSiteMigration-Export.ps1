
function check-ReadyForExport
{
    param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
    
    if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration" `
        -and $Workitem["WorkitemState"] -eq "Scheduled" `
        -and ($Workitem["ProcessingServer"] -is [system.DBNull] -or $Workitem["ProcessingServer"] -eq $env:computername))
    {
        $todaysDate = Get-Date
		#write-host $Workitem["WorkDate"]
        if($Workitem["WorkDate"] -eq 0)
        {    
            # TODO: Claim the workitem!
            return $true
        }
        # TODO: Do something about missed schedules.
    }
    return $false
	#return $true
}
