<#
    This file is for updating the workitem status when someone calls the Send-Email method 
    to send the email manually 
#>

Function Set-WorkItemStateManual_InitialEmail
{
    Param
    (             
        [parameter(Mandatory=$true)] [string] $SourceURL
    )
    Set-WorkItemStateToNow $SourceURL "Scheduled"

}

Function Set-WorkItemStateManual_FinalEmail
{
    Param
    (             
        [parameter(Mandatory=$true)] [string] $SourceURL
    )

    Set-MigrationCompleteToNow $SourceURL

}

Function Set-WorkItemStateManual_DelayedEmail
{
    Param
    (             
        [parameter(Mandatory=$true)] [string] $SourceURL
    )

    Execute-DescheduleSiteMigration -SourceSiteURL $SourceURL -FinalEmailSendDateUTC $UTCTimeNow -RequestedDeschedule $false

}

Function Set-WorkItemStateManual_DescheduledEmail
{
    Param
    (             
        [parameter(Mandatory=$true)] [string] $SourceURL
    )

    Execute-DescheduleSiteMigration -SourceSiteURL $SourceURL -FinalEmailSendDateUTC $UTCTimeNow -RequestedDeschedule $true

}

Function Set-WorkItemStateManual_RollBackEmail
{
    Param
    (             
        [parameter(Mandatory=$true)] [string] $SourceURL
    )

    Execute-CompleteSiteRollback $SourceURL

}

Function Set-WorkItemStateManual_Blockedemail
{
    Param
    (             
        [parameter(Mandatory=$true)] [string] $SourceURL
    )

    Set-MigrationCompleteToNow $SourceURL

}
