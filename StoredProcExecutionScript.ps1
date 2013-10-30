function Execute-UpdateWorkItemState
{
[cmdletbinding()]
    Param
    (   [parameter(Mandatory=$true)] [ValidateLength(0,64)] [string] $WorkitemState,
        [parameter(Mandatory=$true)] [string] $SourceSiteURL,
        [parameter(Mandatory=$false)] [string] $ProcessingServer,
        [parameter(Mandatory=$false)] [int] $ProcessId,
        [parameter(Mandatory=$false)] [datetime] $ProcessStarted,
        [parameter(Mandatory=$false)] [datetime] $ProcessEnded,
        #[parameter(Mandatory=$false)] [datetime] $InitialCommsSendDateUTC,
        [parameter(Mandatory=$false)] [int] $RetryCount,
        [parameter(Mandatory=$false)] [string] $Notes)

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = Get-MigrationCoordinatorConnectionString
    $SqlConnection.Open()

    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
              
    $SqlCmd.CommandText = "EXECUTION_UpdateWorkItemState"
    $SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null
    $SqlCmd.Parameters.Add("@WorkitemState", $WorkitemState) | Out-Null
    if ($PSBoundParameters.ContainsKey("ProcessingServer"))
    {
      $SqlCmd.Parameters.Add("@ProcessingServer", $ProcessingServer) | Out-Null
    }
    if ($PSBoundParameters.ContainsKey("ProcessId"))
    {
        $SqlCmd.Parameters.Add("@ProcessId", $ProcessId) | Out-Null
    }
    if ($PSBoundParameters.ContainsKey("ProcessStarted"))
    {
        $SqlCmd.Parameters.Add("@ProcessStarted", $ProcessStarted) | Out-Null
    }
    if ($PSBoundParameters.ContainsKey("ProcessEnded"))
    {
        $SqlCmd.Parameters.Add("@ProcessEnded", $ProcessEnded) | Out-Null
    }
    #if ($PSBoundParameters.ContainsKey("InitialCommsSendDateUTC"))
    #{
        #$SqlCmd.Parameters.Add("@InitialCommsSendDateUTC", $InitialCommsSendDateUTC) | Out-Null
    #}
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
    $SqlCmd.ExecuteNonQuery() | Out-Null
              
    $SqlConnection.Close();
    return $true # TODO: return a failure if there is one
}
function Execute-UpdateWorkItem
{
[cmdletbinding()]
    Param
    (   [parameter(Mandatory=$true)] [string] $SourceSiteURL,
        [parameter(Mandatory=$false)] [string] $TargetURLOVerride,
        [parameter(Mandatory=$false)] [datetime] $TargetSiteCreated,
        [parameter(Mandatory=$false)] [datetime] $TargetSiteDeleted,
        [parameter(Mandatory=$false)] [datetime] $InitialCommsSendDateUTC,
        [parameter(Mandatory=$false)] [datetime] $FinalCommsSendDateUTC)

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = Get-MigrationCoordinatorConnectionString
    $SqlConnection.Open()

    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
              
    $SqlCmd.CommandText = "EXECUTION_UpdateWorkItem"
    $SqlCmd.Parameters.Add("@SourceSiteURL", $SourceSiteURL) | Out-Null
    if ($PSBoundParameters.ContainsKey("TargetURLOVerride"))
    {
        $SqlCmd.Parameters.Add("@TargetURLOVerride", $TargetURLOVerride) | Out-Null
    }
    if ($PSBoundParameters.ContainsKey("TargetSiteCreated"))
    {
        $SqlCmd.Parameters.Add("@TargetSiteCreated", $TargetSiteCreated) | Out-Null
    }
    if ($PSBoundParameters.ContainsKey("TargetSiteDeleted"))
    {
        $SqlCmd.Parameters.Add("@TargetSiteDeleted", $TargetSiteDeleted) | Out-Null
    }
    if ($PSBoundParameters.ContainsKey("InitialCommsSendDateUTC"))
    {
        $SqlCmd.Parameters.Add("@InitialCommsSendDateUTC", $InitialCommsSendDateUTC) | Out-Null
    }
    if ($PSBoundParameters.ContainsKey("FinalCommsSendDateUTC"))
    {
        $SqlCmd.Parameters.Add("@FinalCommsSendDateUTC", $FinalCommsSendDateUTC) | Out-Null
    }
    $SqlCmd.CommandTimeout = 0
    $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure;          
    $SqlCmd.ExecuteNonQuery() | Out-Null
              
    $SqlConnection.Close();
    return $true # TODO: return a failure if there is one
}

function Execute-CompleteSiteMigration
{
    [cmdletbinding()]
    Param
    (   [parameter(Mandatory=$true)] [string] $SourceSiteURL,
        [parameter(Mandatory=$false)] [datetime] $FinalEmailSendDateUTC,
        [parameter(Mandatory=$false)] [string] $Notes)

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
    $SqlCmd.ExecuteNonQuery() | Out-Null
              
    $SqlConnection.Close();
    return $true # TODO: return a failure if there is one
}

function Execute-CreateMigrationSchedulePreference
{
    [cmdletbinding()]
    Param
    (   [parameter(Mandatory=$true)] [string] $SourceSiteURL,    
        [parameter(Mandatory=$true)] [datetime] $PreferredDateStart,
        [parameter(Mandatory=$true)] [datetime] $PreferredDateEnd,
        [parameter(Mandatory=$true)] [bool] $AllowMigration,
        [parameter(Mandatory=$false)] [string] $Notes)

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = Get-MigrationCoordinatorConnectionString
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
    return $true # TODO: return a failure if there is one
}

function Execute-DescheduleSiteMigration
{
    [cmdletbinding()]
    Param
    (   [parameter(Mandatory=$true)] [string] $SourceSiteURL,
        [parameter(Mandatory=$false)] [datetime] $FinalEmailSendDateUTC,
        [parameter(Mandatory=$false)] [bool] $RequestedDeschedule,
        [parameter(Mandatory=$false)] [string] $Notes)

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = Get-MigrationCoordinatorConnectionString
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
    return $true # TODO: return a failure if there is one
}

function Execute-RemoveMigrationSchedulePreference
{
    [cmdletbinding()]
    Param
    (   [parameter(Mandatory=$true)] [string] $SourceSiteURL,
        [parameter(Mandatory=$true)] [datetime] $PreferredDateStart,
        [parameter(Mandatory=$true)] [datetime] $PreferredDateEnd,
        [parameter(Mandatory=$true)] [bool] $AllowMigration)

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = Get-MigrationCoordinatorConnectionString
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
    return $true # TODO: return a failure if there is one
}

function Execute-DescheduleBlockedSiteMigrationToNow
{
    [cmdletbinding()]
    Param
    (   [parameter(Mandatory=$true)] [string] $SourceURL,
        [parameter(Mandatory=$false)] [string] $Auto_Notes)

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = Get-MigrationCoordinatorConnectionString
    $SqlConnection.Open()

    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandText = "EXECUTION_DescheduleBlockedSiteMigration"
    $SqlCmd.Parameters.Add("@SourceSiteURL", $SourceURL) | Out-Null
	$SqlCmd.Parameters.Add("@FinalEmailSendDateUTC", $($(get-date).ToUniversalTime())) | Out-Null
    if ($PSBoundParameters.ContainsKey("Auto_Notes"))
    {
        $SqlCmd.Parameters.Add("@Notes", $Auto_Notes) | Out-Null
    }

    $SqlCmd.CommandTimeout = 0
    $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure;          
    $SqlCmd.ExecuteNonQuery() | Out-Null
              
    $SqlConnection.Close();
    return $true # TODO: return a failure if there is one
}

function Execute-DescheduleBlockedSiteMigration
{
    [cmdletbinding()]
    Param
    (   [parameter(Mandatory=$true)] [string] $SourceSiteURL,
        [parameter(Mandatory=$false)] [datetime] $FinalEmailSendDateUTC,
        [parameter(Mandatory=$false)] [string] $Notes)

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = Get-MigrationCoordinatorConnectionString
    $SqlConnection.Open()

    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection              
    $SqlCmd.CommandText = "EXECUTION_DescheduleBlockedSiteMigration"
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
    return $true
}