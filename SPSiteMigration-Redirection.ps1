
Set-Alias exec-InsertRedirection Enable-Redirect
Set-Alias exec-DisableRedirection Disable-Redirect

Function check-RedirectRequired
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	#if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`-and $Workitem["WorkitemState"] -eq "RequiresMigrationCompletedComms")
    #{
	    # TODO: Claim the workitem!
	#    return $true
	#}
    return $false
}

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
            Write-Host "`nExample: http://newsite/sitecolletion/sites`n"
            $inputerror = $true
        }
    }
    # TODO: Validate that the starting URL is not redirecting to a site that is being redirected to this site.  (eg. infinite loop)
   
    if($inputerror -eq $true)
    {
        Write-Host "Usage: Enable-Redirect http://somesite.com/sites/yoursite http://newsite.com/sitecolletion/site`n"
        return $false
    }

    trap [Exception] { 
       #write-error $($_.Exception.GetType().FullName); 
       write-error $($_.Exception.Message);
       write-host
       return $false
    }
    
    $foundSite = test-DoesSiteExist $uri2
    if($foundSite -eq $false)
    {
        Write-error "The destination, '$TargetURL' does not exist.`nThe redirection was not inserted into the DB.`n"
        return $false
    }
    
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = Get-URLRedirectConnectionString ($uri1.Scheme + "://" + $uri1.Host)
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
	if($SqlConnection.ConnectionString -eq "")
	{
		return $false
	}
    $SqlConnection.Open()
    $result = $sqlCmd.ExecuteNonQuery()
    $SqlConnection.Close()
    
    Write-Host "Added to Redirection DB..."
    Write-Host "             Starting Url:  $SourceURL"
    Write-Host "          Destination Url:  $TargetURL`n"

    return $true
}

function Disable-Redirect
{ 
    param([parameter(Mandatory=$true)] [string] $SourceURL)
    
    Write-Host ""
    
    $uri1 = $SourceURL -as [System.URI]
    
    if($uri1.AbsoluteURI -eq $null -or $uri1.Scheme -notmatch '[http|https]')
    {
        Write-error "The source URL is not a valid URL:      '$SourceURL'" -category InvalidArgument
        Write-Host "`nUsage: Disable-Redirect http://somesite.com/rootweb/sites/yoursite`n"
        return $false
    } 
    elseif($uri1.LocalPath -match '^/.*/.*/.*|/$|^[^/]' -or $uri1.LocalPath.Split('/').Count -lt 3)
    {
        Write-error "The source URL must be one level off the root sites collection,`nand must not end with a slash: $SourceURL"  -category InvalidArgument
        Write-Host "`nUsage: Disable-Redirect http://somesite.com/rootweb/sites/yoursite`n"
        return $false
    }

    trap [Exception] { 
       #write-error $($_.Exception.GetType().FullName); 
       write-error $($_.Exception.Message);
       write-host ""
       return $false; 
    }
    
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = Get-URLRedirectConnectionString ($uri1.Scheme + "://" + $uri1.Host)
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = "DisableRedirectionUrl"
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
    $SqlCmd.Parameters.Add("OriginalUrlParam", [system.data.SqlDbType]::NVarChar) | out-Null
    $SqlCmd.Parameters['OriginalUrlParam'].Direction = [system.data.ParameterDirection]::Input
	$SqlCmd.Parameters['OriginalUrlParam'].value = $SourceURL
	if($SqlConnection.ConnectionString -eq "")
	{
		return $false
	}
    $SqlConnection.Open()
    $result = $sqlCmd.ExecuteNonQuery()
    $SqlConnection.Close()
    
    Write-Host "Disabled redirection in DB: $SourceURL`n"
    return $true
}

function Verify-UrlIsRedirected
{
    param([parameter(Mandatory=$true)] [string] $SourceURL,
        [parameter(Mandatory=$false)] [string] $TargetURL,
        [parameter(Mandatory=$false)] [string] $ReverseResult)

	$Sucess = $true
	$Failure = $false
    if($ReverseResult -eq "true")
    {
        write-host "Verifying site is not Redirected"
		$Sucess = $false
		$Failure = $true
    }
    else
    {
        write-host "Verifying Redirect"
    }
    write-host "Source:" $SourceURL
    if($TargetURL -ne $null -and $ReverseResult -ne "true")
    {
        write-host "Target:" $TargetURL
    }

    try
    {    
        $req = [System.Net.WebRequest]::Create($SourceURL)
        #$req.Headers.Add(HttpRequestHeader.AcceptEncoding, "gzip,deflate");
        $req.AllowAutoRedirect            = $false
        $req.ProtocolVersion              = new-object Version("1.1")
        $req.PreAuthenticate              = $false
        $req.CachePolicy                  = new-object Net.Cache.RequestCachePolicy([Net.Cache.RequestCacheLevel]::BypassCache)
        $req.UserAgent                    = "MSIT PowerShell Migration Automation"
        $req.ContentType                  = 'text/xml;charset=\"utf-8\"'
        $req.Timeout                      = 0x7530 #30 seconds
        #$req.Proxy                       = New-object System.Net.WebProxy "10.0.0.10:8080"
        #$req.ConnectionGroupName         = Guid.NewGuid().ToString()

    	$creds = Get-FarmCredential $SourceURL
        if($creds -eq $null)
        {
			Write-Host "SharePoint requires credentials in order to verify a redirect."
	        return $Failure  
        }
		$req.Credentials = $creds
		$resp = $req.GetResponse()

        #if($resp.StatusCode -eq [System.Net.HttpStatusCode]::Found)
        #{
            # TODO: Add target URL validation for "found".
        #}

		if($resp.StatusCode -eq [System.Net.HttpStatusCode]::MovedPermanently)
        {
            if($TargetURL -eq $null -or $TargetURL -eq "")
            {
				Write-Host "The site is redirected!"
                return $Sucess
            }
            $respstream = $resp.GetResponseStream()
            $sr = new-object System.IO.StreamReader $respstream; 
            $result = $sr.ReadToEnd()
            $PageXml = new-object xml
            $PageXml.Innerxml = "<WebPage>" + $result + "</WebPage>"
            if($PageXml.WebPage.body -ne $null)
            {
                if($PageXml.WebPage.body.a -ne $null -and $PageXml.WebPage.body.a.HREF -eq $TargetURL)
                {
					Write-Host "The site is redirected to the correct site!"
                    return $Sucess
                }
            }
        }
        if($resp.ResponseUri -eq $TargetURL)
        {
			Write-Host "The site is redirected to the correct site!"
            return $Sucess
        }
    }
    catch [Exception]
    {
        #if ($_.Exception.Message -eq "The remote server returned an error: (403) Forbidden.")
        #{
        #}
        write-error $_.Exception.Message
        return $Failure # Could not verify the redirect, so the test failed.
    }
	Write-Host "The site is not redirected!"
    return $Failure
}