Function Set-SiteReadOnly
{
    Param
    (
        [parameter(Mandatory=$true)]
        [string] $SourceURL
    )
    $start=date
    $processid=[System.Diagnostics.Process]::GetCurrentProcess().id
    Write-Host 'Updating Database: WorkItemState to Making Site ReadOnly for '$SourceURL
    
    #Execute-UpdateWorkItemState -WorkitemState 'Making Site ReadOnly' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start 
    
    $scriptblock={
                    Param($SourceURL)
	                Add-PSSnapin Microsoft.Sharepoint.Powershell 
                    Set-SPSite -Identity $SourceURL -LockState ReadOnly
                 }
    $AppServer=Get-FarmServerName $SourceURL
    $Credential=Get-FarmCredential $SourceURL
    Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $AppServer -ArgumentList $SourceURL #-Authentication Credssp
    Write-Host 'Made Site ReadOnly for ' $SourceURL
}

Function Unlock-Site
{
    Param
    (

        [parameter(Mandatory=$true)]
        [string] $SourceURL
    )
    $start=date
    $processid=[System.Diagnostics.Process]::GetCurrentProcess().id
    Write-Host 'Updating Database: WorkItemState to Unlocking Site for '$SourceURL
    #Execute-UpdateWorkItemState -WorkitemState 'Unlocking Site' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start
    
    $scriptblock={                     
                    Param($SourceURL)
	                Add-PSSnapin Microsoft.Sharepoint.Powershell 
                    Set-SPSite -Identity $SourceURL -LockState Unlock
                 }
    $AppServer=Get-FarmServerName $SourceURL
    $Credential=Get-FarmCredential $SourceURL
    Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $AppServer -ArgumentList $SourceURL #-Authentication Credssp
    Write-Host 'Unlocked Site for ' $SourceURL
}

Function Verify-SiteReadOnly
{
    Param
    (
        [parameter(Mandatory=$true)]
        [string] $SourceURL
    )
    $processid=[System.Diagnostics.Process]::GetCurrentProcess().id
     $scriptblock={
                        Param($SourceURL)
	                    Add-PSSnapin Microsoft.Sharepoint.Powershell 
                        if((Get-SPSite -Identity $SourceURL).ReadOnly)
                         {
                            return $true
                         }
                         else { return $false }
                    }
    $AppServer=Get-FarmServerName $SourceURL
    $Credential=Get-FarmCredential $SourceURL
    $retvalue=Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $AppServer -ArgumentList $SourceURL #-Authentication Credssp
    if($retvalue)
    {
        Write-Host 'Verified site is in ReadOnly state and Updating the Database: WorkItemState to ReadOnly for '$SourceURL
        $end=date
        Execute-UpdateWorkItemState -WorkitemState 'ReadOnly' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessEnded $end
    }
    else
    {
        return $retvalue
    }
    
}
Function Verify-SiteUnlocked
{
 Param
    (
        [parameter(Mandatory=$true)]
        [string] $SourceURL
    )
    
    $Credential=Get-FarmCredential $SourceURL
    $processid=[System.Diagnostics.Process]::GetCurrentProcess().id
    $scriptblock={
                    Param($SourceURL)
	                Add-PSSnapin Microsoft.Sharepoint.Powershell 
                    if(!(Get-SPSite -Identity $SourceURL).ReadOnly)
                     {
                        return $true
                     }
                    else { return $false }
                 }
    $AppServer=Get-FarmServerName $SourceURL
    $retvalue=Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $AppServer -ArgumentList $SourceURL #-Authentication Credssp
    if($retvalue)
    {
        Write-Host 'Verified site is in Unlocked state and Updating the Database: WorkItemState to Unlocked for '$SourceURL
        $end=date
        Execute-UpdateWorkItemState -WorkitemState 'Site Unlocked' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessEnded $end
    }
    else{ return $retvalue }
}
Function Export-Site
{
Param
(
    [parameter(Mandatory=$true)]
    [string] $SourceURL
)
$Credential=Get-FarmCredential $SourceURL
$processid=[System.Diagnostics.Process]::GetCurrentProcess().id
$start=date
Write-Host 'Updating Database: WorkItemState to Exporting Site for '$SourceURL
Execute-UpdateWorkItemState -WorkitemState 'Exporting Site' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start
$AppServer= Get-FarmServerName $SourceURL
$scriptblock={
                        Param($SourceURL,$AppServer)
	                    Add-PSSnapin Microsoft.Sharepoint.Powershell 
                        cd "C:\sptMigration\scripts\MigrationTools v1.7" 
                        . .\MigrationCommands.ps1 
                        #$AppServer='WINDOWS-DRN96U1'
                        $title=$SourceURL.Split("/")[-1] 
                        Export-SPSite -Identity $SourceURL -Path //$AppServer/C$/sptMigration/sites/$title
                    }
Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $AppServer -ArgumentList $SourceURL,$AppServer
}
Function Verify-ExportSite
{
Param
(
    [parameter(Mandatory=$true)]
    [string] $SourceURL
)
$Credential=Get-FarmCredential $SourceURL
$processid=[System.Diagnostics.Process]::GetCurrentProcess().id
$start=date
Write-Host 'Updating Database: WorkItemState to verify Exporting Site for '$SourceURL
#Execute-UpdateWorkItemState -Credential $Credential -WorkitemState 'Exporting Site' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start
$AppServer= Get-FarmServerName $SourceURL

$scriptblock={
                Param($SourceURL)
                $path='C:\sptMigration\Sites\'+$SourceURL.Split("/")[-1]
                if(Test-Path -Path $path)
                {
                    if(((Get-Content $path'\export.log')[-1]).Split(" ")[-2] -eq 0)
                    {
                        return $true
                    }
                    else{ return $false }
                }
                else{ return $false }
}
$retvalue=Invoke-Command -ScriptBlock $scriptblock -Credential $Credential -ComputerName $AppServer -ArgumentList $SourceURL #-Authentication Credssp
if($retvalue)
{
    Write-Host 'Verified the export as Success and Updating the database: WorkItemState as Exported for '$SourceURL
    $end=date
    Execute-UpdateWorkItemState -WorkitemState 'Exported' -SourceSiteURL $SourceURL -ProcessingServer $env:COMPUTERNAME -ProcessId $processid -ProcessStarted $start -ProcessEnded $end
}
else{ return $false }


}
