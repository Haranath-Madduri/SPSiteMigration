Function Check-IsWorkItemInvalid
{
    param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
    $9days  = (Get-Date).Date.AddDays(9)
    $WorkDT = $([datetime]$Workitem["WorkDate"]) 
    # This condition is to check if any workitem is in "RequiresMigrationScheduledComms" state and it is less then 9 days ahead from current date. 
    # we are setting these workitem's status to "RequiresAssistance".
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationScheduledComms"`
        -and $WorkDT -lt $9days )
    { 
        $InvalidError = "The Workitem was found to be too old to send the initial comms."
        Write-Host $InvalidError
        $Workitem["Auto_Notes"] += $InvalidError
	    return $true
	}
}
