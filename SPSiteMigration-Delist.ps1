
function check-ScheduledDelist
{
   	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )

    return $false
}


function Execute-DelistSiteFromMigration
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
    return $true # TODO: return a failure if there is one
}
