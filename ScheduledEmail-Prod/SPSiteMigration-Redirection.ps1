
Set-Alias exec-InsertRedirection Enable-Redirect
Set-Alias exec-DisableRedirection Disable-Redirect

function Enable-Redirect
{ 
    param([parameter(Mandatory=$true)] [string] $SourceURL, 
          [parameter(Mandatory=$true)] [string] $TargetURL)

    $inputerror = $false
    
    Write-Host ""
    
    $uri1 = $SourceURL -as [System.URI]
    if($uri1.AbsoluteURI -eq $null -or $uri1.Scheme -notmatch '[http|https]')
    {
        $inputerror = $true
        Write-error "The source URL is not a valid URL:      '$SourceURL'" -category InvalidArgument
    }

    $uri2 = $TargetURL -as [System.URI]
    if($uri2.AbsoluteURI -eq $null -or $uri2.Scheme -notmatch '[http|https]')
    {
        $inputerror = $true
        Write-error "The destination URL is not a valid URL: '$TargetURL'" -category InvalidArgument
    }
    
    if($inputerror -eq $false)
    {

        if($uri1.LocalPath -match '^/.*/.*/.*|/$|^[^/]' -or $uri1.LocalPath.Split('/').Count -lt 3)
        {
            Write-error "The source URL must be directly off the root sites collection, `nand must not end with a slash: $SourceURL" -category InvalidArgument
            Write-Host "`nExample: http://somesite.com/rootweb/site`n"
            $inputerror = $true
        }
        if($uri2.LocalPath -match '/$')
        {
            Write-error "The destination must not end with a slash, `nand must not be the root: $TargetURL" -category InvalidArgument
            Write-Host "`nExample: http://newsite/rootweb/sitecolletion/sites`n"
            $inputerror = $true
        }
    }
    # TODO: Log to a file/DB
    # TODO: Validate that the starting URL is not redirecting to a site that is being redirected to this site.  (eg. infinite loop)
   
    if($inputerror -eq $true)
    {
        Write-Host "Usage: exec-InsertRedirection http://somesite.com/rootweb/sites/yoursite http://newsite/rootweb/sitecolletion/site`n"
        return
    }

    trap [Exception] { 
       #write-error $($_.Exception.GetType().FullName); 
       write-error $($_.Exception.Message);
       write-host
       return; 
    }
    
    $foundSite = test-DoesSiteExist $uri2
    if($foundSite -eq $false)
    {
        Write-error "The destination, '$TargetURL' does not exist.`nThe redirection was not inserted into the DB.`n"
        return;
    }
    
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = Get-URLRedirectConnectionString($uri1.Scheme + "://" + $uri1.Host)
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = "InsertRedirectionUrl"
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
    $SqlCmd.Parameters.Add("OriginalUrlParam", [system.data.SqlDbType]::NVarChar) | out-Null
    $SqlCmd.Parameters.Add("NewUrlParam", [system.data.SqlDbType]::NVarChar) | out-Null
    $SqlCmd.Parameters['OriginalUrlParam'].Direction = [system.data.ParameterDirection]::Input
    $SqlCmd.Parameters['NewUrlParam'].Direction = [system.data.ParameterDirection]::Input
	$SqlCmd.Parameters['OriginalUrlParam'].value = $SourceURL
    $SqlCmd.Parameters['NewUrlParam'].value = $TargetURL

    $SqlConnection.Open()
    $result = $sqlCmd.ExecuteNonQuery()
    $SqlConnection.Close()
    
    Write-Host "Added to Redirection DB..."
    Write-Host "             Starting Url:  $SourceURL"
    Write-Host "          Destination Url:  $TargetURL`n"
}

function Disable-Redirect
{ 
    param([parameter(Mandatory=$true)] [string] $SourceURL)
    
    Write-Host ""
    
    $uri1 = $SourceURL -as [System.URI]
    
    if($uri1.AbsoluteURI -eq $null -or $uri1.Scheme -notmatch '[http|https]')
    {
        Write-error "The source URL is not a valid URL:      '$SourceURL'" -category InvalidArgument
        Write-Host "`nUsage: exec-DisableRedirection http://somesite.com/rootweb/sites/yoursite`n"
        return
    } 
    elseif($uri1.LocalPath -match '^/.*/.*/.*|/$|^[^/]' -or $uri1.LocalPath.Split('/').Count -lt 3)
    {
        Write-error "The source URL must be one level off the root sites collection,`nand must not end with a slash: $SourceURL"  -category InvalidArgument
        Write-Host "`nUsage: exec-DisableRedirection http://somesite.com/rootweb/sites/yoursite`n"
        return
    }

    # TODO: Log to a file/DB
  
    trap [Exception] { 
       #write-error $($_.Exception.GetType().FullName); 
       write-error $($_.Exception.Message);
       write-host ""
       return; 
    }
    
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = Get-URLRedirectConnectionString($uri1.Scheme + "://" + $uri1.Host)
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = "DisableRedirectionUrl"
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
    $SqlCmd.Parameters.Add("OriginalUrlParam", [system.data.SqlDbType]::NVarChar) | out-Null
    $SqlCmd.Parameters['OriginalUrlParam'].Direction = [system.data.ParameterDirection]::Input
	$SqlCmd.Parameters['OriginalUrlParam'].value = $SourceURL

    $SqlConnection.Open()
    $result = $sqlCmd.ExecuteNonQuery()
    $SqlConnection.Close()
    
    Write-Host "Disabled redirection in DB: $SourceURL`n"
}
