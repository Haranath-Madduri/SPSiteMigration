. .\SPSiteMigration.ps1
$wi = Read-CurrentWorkItems -WorkDate $(Get-Date).Date.AddDays(11)
$SourceUrl = "http://sharepointasia/sites/OneFinance-South Africa"

if($wi.Tables[0].Columns["Auto_SequenceStartTimeUTC"] -eq $null)
{
	$wi.Tables[0].Columns.Add("Auto_SequenceStartTimeUTC", [DateTime]) | Out-Null	# Keep track of the sequence start time.
	$wi.Tables[0].Columns.Add("Auto_StepStartTimeUTC", [DateTime]) | Out-Null		# Keep track of the step start time.
	$wi.Tables[0].Columns.Add("Auto_MaxParallelRate", [int]) | Out-Null 			# Count the work Items for each Farm.
	$wi.Tables[0].Columns.Add("Auto_LastRetryCount", [int]) | Out-Null 				# Count Retries.
	$wi.Tables[0].Columns.Add("Auto_Notes", [string]) | Out-Null 					# Notes which will be added to the status.
	$wi.Tables[0].Columns.Add("Auto_WorkingTimeEndOffset", [TimeSpan]) | Out-Null 
}
$item = $wi.Tables[0] | ? {$_.SourceURL -eq $SourceUrl}
if($item -eq $null)
{
	Write-Error "Didn't find $SourceUrl in the list of workitems."
}

$item["Auto_MaxParallelRate"] = 10
$item["Auto_LastRetryCount"] = 0
$item["Auto_Notes"] = ""
$item["Auto_WorkingTimeEndOffset"] = "06:00:00" -as [TimeSpan]

if ($item -ne $null)
{
	Write-Host "`nValidating triggers for '$SourceUrl':`n"
	Write-Host "check-ReadyForInitialEmail:                 " $(check-ReadyForInitialEmail $item)
	Write-Host "check-ReadyForFinalEmail:                   " $(check-ReadyForFinalEmail $item)
	Write-Host "check-ReadyForDescheduledEmail:             " $(check-ReadyForDescheduledEmail $item)
	Write-Host "check-ReadyForDelayedEmail:                 " $(check-ReadyForDelayedEmail $item)
	Write-Host "check-ReadyForRollBackEmail:                " $(check-ReadyForRollBackEmail $item)
	Write-Host "check-ReadyForDelistedEmail:                " $(check-ReadyForDelistedEmail $item)
	Write-Host "check-ReadyForBlockedEmail:                 " $(check-ReadyForBlockedEmail $item)
    Write-Host "check-ReadyForMigrationAutomation:          " $(check-ReadyForMigrationAutomation $item)
	
	$TodaysDate 				= Get-Date
	$StartDate 					= $($item["WorkDate"]).Add($($item["WorkingTimeStartOffset"]))
	$TimeZoneOffset 			= $item["TimeZoneOffset"]
	if($TimeZoneOffset.GetType() -eq [String])				# Someday $TimeZoneOffset may be a timespan instead of a string.
	{
		$StartingChar 			= $TimeZoneOffset[0]
		if($StartingChar -lt '0' -or $StartingChar -gt 9)
		{
			$TimeZoneOffset 	= $TimeZoneOffset.TrimStart($StartingChar)
		}
		$TimeZoneOffset 		= $TimeZoneOffset -as [TimeSpan]
		if($StartingChar -eq '-')
		{
			$TimeZoneOffset 	= $TimeZoneOffset.Negate()
		}
	}
    $TodaysUTCDate 				= $TodaysDate.ToUniversalTime()
	$StartUTCDate 				= $StartDate.Subtract($TimeZoneOffset)	# Depending on the database, the value could be reveresed.

	$TimeFromNow 				= $StartDate - $TodaysDate
	$UTCTimeFromNow 			= $StartUTCDate - $TodaysUTCDate
	
	Write-Host "`nCommonly used Info:`n"
	Write-Host "        WorkDate:                           '$StartDate'"
	Write-Host "'Local' time for scheduling:                $($TimeFromNow.Days) Days, $($TimeFromNow.Hours) Hours, and $($TimeFromNow.Minutes) Minutes from now." 
	Write-Host "'UTC' and DB config for scheduling:         $($UTCTimeFromNow.Days) Days, $($UTCTimeFromNow.Hours) Hours, and $($UTCTimeFromNow.Minutes) Minutes from now." 
	Write-Host "WorkItemTypeName:                           '$($item.WorkItemTypeName)'"
	Write-Host "WorkitemState:                              '$($item.WorkitemState)'"
    Write-Host "ProcessingServer:                           '$($item.ProcessingServer)'"

   	$9days  = (Get-Date).Date.AddDays(9)
    $11days = (Get-Date).Date.AddDays(11)
    $WorkDT = $([datetime]$item["WorkDate"])

	Write-Host "`nBreakout Tests...`n"
	Write-Host "Scheduled Migration Test:                   " $($item["WorkItemTypeName"] -eq "Scheduled Migration")
	Write-Host "RequiresMigrationScheduledComms Test:       " $($item["WorkitemState"] -eq "RequiresMigrationScheduledComms")
	Write-Host "RequiresMigrationCompletedComms Test:       " $($item["WorkitemState"] -eq "RequiresMigrationCompletedComms")
	Write-Host "RequiresMigrationDelayedComms Test:         " $($item["WorkitemState"] -eq "RequiresMigrationDelayedComms")
	Write-Host "RequiresMigrationExecutionDelayedComms Test:" $($item["WorkitemState"] -eq "RequiresMigrationExecutionDelayedComms")
	Write-Host "RequiresMigrationRollbackComms Test:        " $($item["WorkitemState"] -eq "RequiresMigrationRollbackComms")
	Write-Host "RequiresMigrationDelistedComms Test:        " $($item["WorkitemState"] -eq "RequiresMigrationDelistedComms")
    Write-Host ">= Nine Day Test:                           " $($WorkDT -ge $9days)
    Write-Host "< Eleven Day Test:                          " $($WorkDT -lt $11days)
	Write-Host "Waited an hour since last change:           " $($(Get-Date) -ge $($item["WorkItemStateLastModified"]).AddHours(1))
	
}
else
{
	Write-Host "The site '$SourceUrl' is not recognized as a workitem within the next 11 days"
}
Write-Host ""

# WorkDate : 10/18/2013 12:00:00 AM
# WorkingTimeStartOffset : 22:00:00
# TimeZoneOffset : +08:00
# WebAppShortName : SPSASIA
# SourceURL : http://sharepointasia/sites/esreadiness_sur
# TargetURL : https://microsoft.sharepoint.com/teams/esreadiness_sur
# SiteId : 0173e5df-1285-4f6a-a690-3e5446e986c3
# WebAppId : 1afca5f5-e2de-49c4-8c0a-a5da56c3d5d8
# SiteTemplate : STS#1
# SiteLanguage : 1041
# SiteCollectionSize : 1438492
# OwnerLogin : FAREAST\erichida
# OwnerEmail : erichida@microsoft.com
# SiteAdministratorLogins : FAREAST\a-chiak; FAREAST\erichida; FAREAST\mahagi
# SiteAdministratorEmailAddresses : a-chiak@microsoft.com; erichida@microsoft.com; Masahiro.Hagiwara@microsoft.com
# RequiresWorkFlowMigration : False
# WorkitemId : 8478
# WorkitemType : 1
# WorkItemTypeName : Scheduled Migration
# InitialCommsSendDateUTC :
# WorkItemLastModified : 9/30/2013 10:58:37 PM
# WorkitemStateId : 38640
# WorkitemState : RequiresMigrationScheduledComms
# ProcessingServer :
# ProcessId : 0
# ProcessStarted :
# ProcessEnded :
# RetryCount : 0
# WorkItemStateLastModified : 10/8/2013 7:15:16 PM
