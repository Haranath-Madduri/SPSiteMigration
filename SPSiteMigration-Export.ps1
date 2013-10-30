
function check-ReadyForMigrationAutomation
{
    param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
    
    if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration" `
        -and $Workitem["WorkitemState"] -eq "Scheduled" )
    {
        #-and ($Workitem["ProcessingServer"] -is [system.DBNull] -or $Workitem["ProcessingServer"] -eq $env:computername))
		
        # Don't start it if there are already a bunch of tasks running:
		$NumRunning = Get-NumberOfActiveSequences $Workitem["WebAppID"]
        if($workitem["Auto_MaxParallelRate"] -gt $NumRunning)
        {
            $TodaysDate 				= Get-Date
			$StartDate 					= $($workitem["WorkDate"]).Add($($workitem["WorkingTimeStartOffset"]))
			$StopDate 					= $StartDate.Add($Workitem["Auto_WorkingTimeEndOffset"])
			
			# Default to evaluating with UTC time, but allow the automation to use the local machine time if it's in the same region:
			if($global:GlobalSettings.AutomationData.UseLocalTime -ne "true")
			{
				$TimeZoneOffset 		= $Workitem["TimeZoneOffset"]
				if($TimeZoneOffset.GetType() -eq [String])				# Someday $TimeZoneOffset may be a timespan instead of a string.
				{
					$StartingChar 		= $TimeZoneOffset[0]
					if($StartingChar -lt '0' -or $StartingChar -gt 9)
					{
						$TimeZoneOffset = $TimeZoneOffset.TrimStart($StartingChar)
					}
					$TimeZoneOffset 	= $TimeZoneOffset -as [TimeSpan]
					if($StartingChar -eq '-')
					{
						$TimeZoneOffset = $TimeZoneOffset.Negate()
					}
				}
	            $TodaysDate 			= $TodaysDate.ToUniversalTime()
				$StartDate 				= $StartDate.Subtract($TimeZoneOffset)	# Depending on the database, the value could be reveresed.
				$StopDate 				= $StartDate.Add($Workitem["Auto_WorkingTimeEndOffset"])
			}
            if($TodaysDate -gt $StartDate -and $TodaysDate -lt $StopDate)
            {
				Write-Host $NumRunning "threads are running."

                # TODO: Claim the workitem!
                return $true
            }
            # TODO: Do something about missed schedules.
        }
    }
    return $false
}
