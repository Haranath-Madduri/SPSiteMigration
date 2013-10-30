function Execute-UpdateWorkItemState
{
[cmdletbinding()]
Param
(             
    [parameter(Mandatory=$true)]
    [ValidateLength(0,64)]
    [string] $NewWorkitemState,
    
    [parameter(Mandatory=$true)]
    [string] $SourceURL,
    
    [parameter(Mandatory=$false)]
    [string] $ProcessingServer,

    [parameter(Mandatory=$false)]
    [int] $ProcessId,

    [parameter(Mandatory=$false)]
    [datetime] $ProcessStartedTime,

    [parameter(Mandatory=$false)]
    [datetime] $ProcessEndedTime,

    [parameter(Mandatory=$false)]
    [datetime] $InitialUTCCommsSendDateTime,

    [parameter(Mandatory=$false)]
    [int] $RetryCount,

    [parameter(Mandatory=$false)]
    [string] $Notes
)
write-host "Execute-UpdateWorkItemState" $NewWorkitemState $SourceURL
$Credential=Get-MigrationCoordinatorCredential

$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$sqlConnection.ConnectionString =  Get-MigrationCoordinatorConnectionString
$SqlConnection.Open()

$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.Connection = $SqlConnection
              
$SqlCmd.CommandText = "EXECUTION_UpdateWorkItemState"
$SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null
$SqlCmd.Parameters.Add("@WorkitemState", $NewWorkitemState) | Out-Null
if ($PSBoundParameters.ContainsKey("ProcessingServer"))
{
  $SqlCmd.Parameters.Add("@ProcessingServer", $ProcessingServer) | Out-Null
}
if ($PSBoundParameters.ContainsKey("ProcessId"))
{
    $SqlCmd.Parameters.Add("@ProcessId", $ProcessId) | Out-Null
}
if ($PSBoundParameters.ContainsKey("ProcessStartedTime"))
{
    $SqlCmd.Parameters.Add("@ProcessStarted", $ProcessStartedTime) | Out-Null
}
if ($PSBoundParameters.ContainsKey("ProcessEndedTime"))
{
    $SqlCmd.Parameters.Add("@ProcessEnded", $ProcessEndedTime) | Out-Null
}
if ($PSBoundParameters.ContainsKey("InitialUTCCommsSendDateTime"))
{
    $SqlCmd.Parameters.Add("@InitialCommsSendDateUTC", $InitialUTCCommsSendDateTime) | Out-Null
}
if ($PSBoundParameters.ContainsKey("RetryCount"))
{
    $SqlCmd.Parameters.Add("@RetryCount", $RetryCount) | Out-Null
}
if ($PSBoundParameters.ContainsKey("Notes"))
{
    $SqlCmd.Parameters.Add("@Notes", $Notes) | Out-Null
}
$SqlCmd.CommandTimeout = 0
$SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure;          
              
#$SqlCmd.ExecuteNonQuery() | Out-Null
              
$SqlConnection.Close(); 
}

function Execute-CompleteSiteMigration
{
[cmdletbinding()]
Param
(    
    [parameter(Mandatory=$true)]
    [string] $SourceURL,

    [parameter(Mandatory=$false)]
    [datetime] $FinalEmailSendDateUTC,

    [parameter(Mandatory=$false)]
    [string] $Notes
)
    $Credential=Get-MigrationCoordinatorCredential
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = Get-MigrationCoordinatorConnectionString
    $SqlConnection.Open()

    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
              
    $SqlCmd.CommandText = "EXECUTION_CompleteSiteMigration"
    $SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null

    if ($PSBoundParameters.ContainsKey("FinalEmailSendDateUTC"))
    {
        $SqlCmd.Parameters.Add("@FinalEmailSendDateUTC", $FinalEmailSendDateUTC) | Out-Null
    }
    if ($PSBoundParameters.ContainsKey("Notes"))
    {
        $SqlCmd.Parameters.Add("@Notes", $Notes) | Out-Null
    }

    $SqlCmd.CommandTimeout = 0
    $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure;          
              
    #$SqlCmd.ExecuteNonQuery() | Out-Null
    $SqlConnection.Close(); 
}

function Execute-CompleteSiteRollback
{
[cmdletbinding()]
Param
(    
    [parameter(Mandatory=$true)]
    [string] $SourceSiteURL,

    [parameter(Mandatory=$false)]
    [datetime] $FinalEmailSendDateUTC,
    
    [parameter(Mandatory=$false)]
    [string] $Notes
)
$Credential=Get-MigrationCoordinatorCredential
$ConnectionString = "Server=mfha6tk8ej.database.windows.net;Database=Migration_Coordinator_Dev; UID=$($Credential.UserName);password=$($Credential.GetNetworkCredential().Password); Integrated Security=$false;Connect Timeout=180;"

$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$sqlConnection.ConnectionString = $ConnectionString;
$SqlConnection.Open()

$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.Connection = $SqlConnection
              
$SqlCmd.CommandText = "EXECUTION_CompleteSiteRollback"
$SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null

if ($PSBoundParameters.ContainsKey("FinalEmailSendDateUTC"))
{
$SqlCmd.Parameters.Add("@FinalEmailSendDateUTC", $FinalEmailSendDateUTC) | Out-Null
}
if ($PSBoundParameters.ContainsKey("Notes"))
{
    $SqlCmd.Parameters.Add("@Notes", $Notes) | Out-Null
}

$SqlCmd.CommandTimeout = 0
$SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure;          
              
$SqlCmd.ExecuteNonQuery() | Out-Null
              
$SqlConnection.Close(); 
}
function Execute-CreateMigrationSchedulePreference
{
[cmdletbinding()]
Param
(    
    [parameter(Mandatory=$true)]
    [string] $SourceSiteURL,    

    [parameter(Mandatory=$true)]
    [datetime] $PreferredDateStart,

    [parameter(Mandatory=$true)]
    [datetime] $PreferredDateEnd,

    [parameter(Mandatory=$true)]
    [bool] $AllowMigration,

    [parameter(Mandatory=$false)]
    [string] $Notes
)
$Credential=Get-MigrationCoordinatorCredential
$ConnectionString = "Server=mfha6tk8ej.database.windows.net;Database=Migration_Coordinator_Dev; UID=$($Credential.UserName);password=$($Credential.GetNetworkCredential().Password); Integrated Security=$false;Connect Timeout=180;"

$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$sqlConnection.ConnectionString = $ConnectionString;
$SqlConnection.Open()

$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.Connection = $SqlConnection
              
$SqlCmd.CommandText = "EXECUTION_CreateMigrationSchedulePreference"
$SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null
$SqlCmd.Parameters.Add("@PreferredDateStart", $PreferredDateStart) | Out-Null
$SqlCmd.Parameters.Add("@PreferredDateEnd", $PreferredDateEnd) | Out-Null
$SqlCmd.Parameters.Add("@AllowMigration", $AllowMigration) | Out-Null
if ($PSBoundParameters.ContainsKey("Notes"))
{
    $SqlCmd.Parameters.Add("@Notes", $Notes) | Out-Null
}

$SqlCmd.CommandTimeout = 0
$SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure;          
              
$SqlCmd.ExecuteNonQuery() | Out-Null
              
$SqlConnection.Close(); 
}
function Execute-DescheduleSiteMigration
{
[cmdletbinding()]
Param
(    
    [parameter(Mandatory=$true)]
    [string] $SourceSiteURL,

    [parameter(Mandatory=$false)]
    [datetime] $FinalEmailSendDateUTC,

    [parameter(Mandatory=$false)]
    [bool] $RequestedDeschedule,
        
    [parameter(Mandatory=$false)]
    [string] $Notes
)
$Credential=Get-MigrationCoordinatorCredential
$ConnectionString = "Server=mfha6tk8ej.database.windows.net;Database=Migration_Coordinator_Dev; UID=$($Credential.UserName);password=$($Credential.GetNetworkCredential().Password); Integrated Security=$false;Connect Timeout=180;"

$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$sqlConnection.ConnectionString = $ConnectionString;
$SqlConnection.Open()

$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.Connection = $SqlConnection
              
$SqlCmd.CommandText = "EXECUTION_DescheduleSiteMigration"
$SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null
if ($PSBoundParameters.ContainsKey("FinalEmailSendDateUTC"))
{
    $SqlCmd.Parameters.Add("@FinalEmailSendDateUTC", $FinalEmailSendDateUTC) | Out-Null
}
if ($PSBoundParameters.ContainsKey("RequestedDeschedule"))
{
    $SqlCmd.Parameters.Add("@RequestedDeschedule", $RequestedDeschedule) | Out-Null
}
if ($PSBoundParameters.ContainsKey("Notes"))
{
    $SqlCmd.Parameters.Add("@Notes", $Notes) | Out-Null
}

$SqlCmd.CommandTimeout = 0
$SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure;          
              
$SqlCmd.ExecuteNonQuery() | Out-Null
              
$SqlConnection.Close(); 
}
function Execute-DelistSiteFromMigration
{
[cmdletbinding()]
Param
(    
    [parameter(Mandatory=$true)]
    [string] $SourceSiteURL,

    [parameter(Mandatory=$false)]
    [datetime] $FinalEmailSendDateUTC,
        
    [parameter(Mandatory=$false)]
    [string] $Notes
)
$Credential=Get-MigrationCoordinatorCredential
$ConnectionString = "Server=mfha6tk8ej.database.windows.net;Database=Migration_Coordinator_Dev; UID=$($Credential.UserName);password=$($Credential.GetNetworkCredential().Password); Integrated Security=$false;Connect Timeout=180;"

$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$sqlConnection.ConnectionString = $ConnectionString;
$SqlConnection.Open()

$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.Connection = $SqlConnection
              
$SqlCmd.CommandText = "EXECUTION_DelistSiteFromMigration"
$SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null
if ($PSBoundParameters.ContainsKey("FinalEmailSendDateUTC"))
{
    $SqlCmd.Parameters.Add("@FinalEmailSendDateUTC", $FinalEmailSendDateUTC) | Out-Null
}
if ($PSBoundParameters.ContainsKey("Notes"))
{
    $SqlCmd.Parameters.Add("@Notes", $Notes) | Out-Null
}

$SqlCmd.CommandTimeout = 0
$SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure;          
              
$SqlCmd.ExecuteNonQuery() | Out-Null
              
$SqlConnection.Close(); 
}
function Execute-InitiateRequestedSiteRollback
{
[cmdletbinding()]
Param
(    
[parameter(Mandatory=$true)]
[string] $SourceSiteURL
)
$Credential=Get-MigrationCoordinatorCredential
$ConnectionString = "Server=mfha6tk8ej.database.windows.net;Database=Migration_Coordinator_Dev; UID=$($Credential.UserName);password=$($Credential.GetNetworkCredential().Password); Integrated Security=$false;Connect Timeout=180;"

$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$sqlConnection.ConnectionString = $ConnectionString;
$SqlConnection.Open()

$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.Connection = $SqlConnection
              
$SqlCmd.CommandText = "EXECUTION_InitiateRequestedSiteRollback"
$SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null
$SqlCmd.CommandTimeout = 0
$SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure;          
              
$SqlCmd.ExecuteNonQuery() | Out-Null
              
$SqlConnection.Close(); 
}
function Execute-RemoveMigrationSchedulePreference
{
[cmdletbinding()]
Param
(    
    [parameter(Mandatory=$true)]
    [string] $SourceSiteURL,

    [parameter(Mandatory=$true)]
    [datetime] $PreferredDateStart,

    [parameter(Mandatory=$true)]
    [datetime] $PreferredDateEnd,

    [parameter(Mandatory=$true)]
    [bool] $AllowMigration
)
$Credential=Get-MigrationCoordinatorCredential
$ConnectionString = "Server=mfha6tk8ej.database.windows.net;Database=Migration_Coordinator_Dev; UID=$($Credential.UserName);password=$($Credential.GetNetworkCredential().Password); Integrated Security=$false;Connect Timeout=180;"

$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$sqlConnection.ConnectionString = $ConnectionString;
$SqlConnection.Open()

$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.Connection = $SqlConnection
              
$SqlCmd.CommandText = "EXECUTION_RemoveMigrationSchedulePreference"
$SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null
$SqlCmd.Parameters.Add("@PreferredDateStart", $PreferredDateStart) | Out-Null
$SqlCmd.Parameters.Add("@PreferredDateEnd", $PreferredDateEnd) | Out-Null
$SqlCmd.Parameters.Add("@AllowMigration", $AllowMigration) | Out-Null
$SqlCmd.CommandTimeout = 0
$SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure;          
              
$SqlCmd.ExecuteNonQuery() | Out-Null
              
$SqlConnection.Close(); 
}
