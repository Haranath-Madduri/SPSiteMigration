function Get-WorkItems
{
    param  ([parameter(Mandatory=$false)] [DateTime] $StartDate,
            [parameter(Mandatory=$false)] [DateTime] $EndDate,
            [parameter(Mandatory=$false)] [string] $FarmUrl)

    $RetDataset = new-object System.Data.Dataset
    
    trap [Exception] { 
       write-error $($_.Exception.Message);
       write-host ""
       return $RetDataset; 
    }
    
    
    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		Write-Host "    Reading from the Coordinator Database"  "" -nonewline

		$SqlConnection 								= New-Object System.Data.SqlClient.SqlConnection
		$SqlConnection.ConnectionString				= Get-MigrationCoordinatorConnectionString
        $SqlCmd 									= New-Object System.Data.SqlClient.SqlCommand
        $SqlCmd.CommandText 						= "EXECUTION_GetWorkItems"
        $SqlCmd.Connection 							= $SqlConnection
        $SqlCmd.CommandType 						= [System.Data.CommandType]::StoredProcedure
        $SqlCmd.Parameters.Add("StartDate", [system.data.SqlDbType]::date) | out-Null
        $SqlCmd.Parameters.Add("EndDate",   [system.data.SqlDbType]::date) | out-Null
        $SqlCmd.Parameters.Add("WebAppId",  [system.data.SqlDbType]::uniqueidentifier) | out-Null
        $SqlCmd.Parameters['StartDate'].Direction 	        = [system.data.ParameterDirection]::Input
        $SqlCmd.Parameters['EndDate'].Direction 	        = [system.data.ParameterDirection]::Input
        $SqlCmd.Parameters['WebAppId'].Direction 	= [system.data.ParameterDirection]::Input
            

        if($StartDate -ne $null)
        {
            $SqlCmd.Parameters['StartDate'].value    = $StartDate  
        }
        else
        {
            $SqlCmd.Parameters['StartDate'].value    = [DBNull]::Value
        }

        if($EndDate -ne $null)
        {
            $SqlCmd.Parameters['EndDate'].value    = $EndDate  
        }
        else
        {
            $SqlCmd.Parameters['EndDate'].value    = [DBNull]::Value
        }
              
        if($FarmUrl -eq $null -or $FarmUrl -eq "")
        {
            $SqlCmd.Parameters['WebAppId'].value 	= [DBNull]::Value
        } 
        else        
        {
            if($FarmUrl.ToLower().Trim() -eq "http://sharepoint")
            {
                $SqlCmd.Parameters['WebAppId'].value 	= New-object Guid('74A5C7A2-2560-4A4C-8AC9-3B5231834114')
            }
            elseif($FarmUrl.ToLower().Trim() -eq "http://sharepointemea")
            {
                $SqlCmd.Parameters['WebAppId'].value 	= New-object Guid('AAD0F941-DB37-40B0-83E8-8FD4915E2864')
            }
            elseif($FarmUrl.ToLower().Trim() -eq "http://sharepointasia")
            {
                $SqlCmd.Parameters['WebAppId'].value 	= New-object Guid('1AFCA5F5-E2DE-49C4-8C0A-A5DA56C3D5D8')
            }
            elseif($FarmUrl.ToLower().Trim() -eq "http://team")
            {
                $SqlCmd.Parameters['WebAppId'].value 	= New-object Guid('309A68E1-A464-4B00-9DDD-C725C75C780C')
            }
            else
            {
                $SqlCmd.Parameters['WebAppId'].value 	= [DBNull]::Value
            }
            
        }
			
        $dataset = new-object System.Data.Dataset 
        $DataAdapter = new-object System.Data.SqlClient.SqlDataAdapter $SqlCmd
        $DataAdapter.Fill($dataset) | out-Null
        if($dataset.Tables.Count -gt 0)
        {
            $RetDataset.Merge($dataset) | out-Null
        }

		Write-Host "completed.`n"
    }
    return $RetDataset
}




function Create-SPOSite
{
    param  ([parameter(Mandatory=$false)] [DateTime] $StartDate,
            [parameter(Mandatory=$false)] [DateTime] $EndDate,
            [parameter(Mandatory=$false)] [string] $FarmUrl)

    trap [Exception] { 
       write-error $($_.Exception.Message);
       write-host ""
       #return $RetDataset; 
    }
    $logPath  = $(Get-Location).Path + "\logs\SPOSiteCreationlog.txt"
    $result    = Get-WorkItems -StartDate $StartDate -EndDate $EndDate -FarmUrl $FarmUrl
    
    foreach($row in $result.Tables.Rows)
    {
        if($row.WorkitemState.Trim() -eq "Planned" -or $row.WorkitemState.Trim() -eq "Scheduled" ) # need to remove scheduled condition once backlog is cleared
        {
            Add-Content -Path $logPath -Value "***********************************************************************"
            Add-Content -Path $logPath -Value  ("Start Time: "+ $(Get-Date) )
            Add-Content -Path $logPath -Value  ("Target URL of the work item: " +  $row.TargetURL)
            if($row.TargetURL.Trim() -ne $null -or $row.TargetURL.Trim() -ne "")
            {
                Write-Host "**********************************************************************************************************"
                Write-Host "Starting Provisioning process on site with URL***** " $row.TargetURL.Trim() "****** ."
                try
                {
                    $site = Get-SPOSite -Id $row.TargetURL.Trim()
                    if($site.Status -eq "active")
                    {
                        Write-Error "Site already exists." 
                    }
                    write-host "Setting the status to RequiresAssistance.Please check the status of this site in SPO." 
                    Add-Content -Path $logPath -Value  ("`r`nPlease check the status of this site in SPO. Setting the status to RequiresAssistance..." + "`r`nEnd Time: "+ $(Get-Date))    
                    Set-WorkItemStateToNow -SourceURL $row.SourceURL -NextWorkitemState "RequiresAssistance" -Auto_Notes "Provisioning AUtomation: Site already exists"
                    Write-Host "**********************************************************************************************************"
                    continue
                }
                catch [Exception]
                {
                    #Write-Error $($_.Exception.Message)
                    Write-Host "Target site available in SPO.`n Gathering info for site creation."
                }
                
                    $newSiteUrl   = $row.TargetURL.Trim()
                    if($row.OwnerLogin.Trim() -eq $null -or $row.OwnerLogin.Trim() -eq "")
                    {
                        Write-Error "Owner email is empty. Setting the status to RequiresAssistance..." 
                        Add-Content -Path $logPath -Value  ("`r`nOwner email is empty. Setting the status to RequiresAssistance..." + "`r`nEnd Time: "+ $(Get-Date))
                        Set-WorkItemStateToNow -SourceURL $row.SourceURL -NextWorkitemState "RequiresAssistance" -Auto_Notes "Provisioning AUtomation: Owner email is empty."
                        Write-Host "**********************************************************************************************************"
                        continue                       
                    }
                    $SplitOwner   = $row.OwnerLogin.Trim().Split('\')
                    $OwnerDomain  = $SplitOwner[0].Trim()
                    $OwnerAlies   = $SplitOwner[1].Trim()
                    if($OwnerDomain -ne $null -and $OwnerDomain -eq "NTDEV")
                    {
                        $OwnerEmail   = $OwnerAlies+"@NTDEV.microsoft.com"
                    }
                    else
                    {
                        $OwnerEmail   = $OwnerAlies+"@microsoft.com"
                    }

                    $1GBUnitinBytes = 1024*1024*1024 #1073741824
                    if($row.SiteCollectionSize -ne $null)
                    {
                        if($row.SiteCollectionSize -lt $1GBUnitinBytes*10)
                        {
                            $StorageQuotaMB = 10*1024
                        }
                        elseif($row.SiteCollectionSize -ge $1GBUnitinBytes*10)
                        {
                            $currentSizeByte  = $row.SiteCollectionSize/$1GBUnitinBytes
                            $RoundOffSizeGB   = [Math]::Round($currentSizeByte,0)   
                            $StorageQuotaMB   = ($RoundOffSizeGB +3)*1024
                        }
                    }
                    else
                    {
                        Write-Error "Check the Value of SiteCollectionSize. Setting the status to RequiresAssistance..."
                        Add-Content -Path $logPath -Value  ("`r`nCheck the Value of SiteCollectionSize. Setting the status to RequiresAssistance..." + "`r`nEnd Time: "+ $(Get-Date))
                        Set-WorkItemStateToNow -SourceURL $row.SourceURL -NextWorkitemState "RequiresAssistance" -Auto_Notes "Provisioning AUtomation: Check the Value of SiteCollectionSize"
                        Write-Host "**********************************************************************************************************"
                        continue
                    }
                    try
                    {
                        Write-Host "Starting the execution of SPO command New-SPOSite..... with values:  " 
                        Write-Host "Owner: " $OwnerEmail
                        Write-Host "StorageQuotaMB: " $StorageQuotaMB
                        Add-Content -Path $logPath -Value  ("Creating the site with values:`r`nOWNER( "+ $OwnerEmail + ") `r`nStorageQuotaMB( "+ $StorageQuotaMB +")")
                        New-SPOSite -Url $newSiteUrl -Owner $OwnerEmail -StorageQuota $StorageQuotaMB -LocaleId $row.SiteLanguage -CompatibilityLevel 14 -ResourceQuota 300
                        Write-Host "Setting*** O365MA01@microsoft.com *** to the site admins..."
                        Add-Content -Path $logPath -Value "Setting*** O365MA01 *** user to the site admins..." 
                        Set-SPOUser -Site  $newSiteUrl -LoginName O365MA01@microsoft.com -IsSiteCollectionAdmin $true
	                    #Start-Sleep -seconds 5
                        
                        if($row.WorkitemState.Trim() -eq "Planned" )
                        {
                            Write-Host "Site Created successfully!!!!. Updating TargetSiteCreated date, TargetURLOVerride and STATUS after creation of site...."
                            Execute-UpdateWorkItem -SourceSiteURL $row.SourceURL -TargetURLOVerride  $newSiteUrl -TargetSiteCreated $(Get-Date).ToUniversalTime()
                            Set-WorkItemStateToNow -SourceURL $row.SourceURL -NextWorkitemState "RequiresMigrationScheduledComms" -Auto_Notes "Provisioning AUtomation: status updated to RequiresMigrationScheduledComms"
                            Add-Content -Path $logPath -Value  "Site Created successfully!!!!. Updating TargetSiteCreated date, TargetURLOVerride and STATUS after creation of site...."
                        }
                        if($row.WorkitemState.Trim() -eq "Scheduled" )
                        {
                            Write-Host "Site Created successfully!!!!. Updating TargetSiteCreated date, TargetURLOVerride and STATUS after creation of site...."
                            Execute-UpdateWorkItem -SourceSiteURL $row.SourceURL -TargetURLOVerride  $newSiteUrl -TargetSiteCreated $(Get-Date).ToUniversalTime() 
                            Set-WorkItemStateToNow -SourceURL $row.SourceURL -NextWorkitemState "scheduled" -Auto_Notes "Provisioning AUtomation: status updated to scheduled"
                            Add-Content -Path $logPath -Value  "Site Created successfully!!!!. Updating TargetSiteCreated date, TargetURLOVerride and STATUS after creation of site...."
                        }

	                    Add-Content -Path $logPath -Value  ("End Time: "+ $(Get-Date) )
                        Write-Host "**********************************************************************************************************"
                    }
                    catch [Exception]
                    {
                        Write-Error ("There is an error while creating the site:(***" +$row.TargetURL.Trim() + "****) ")
                        Add-Content -Path $logPath -Value  ("Powershell Exception: "+$_.Exception.Message)
                        Add-Content -Path $logPath -Value  ( "Failed to create site" + "`r`nEnd Time: "+ $(Get-Date))
                        Add-Content -Path $logPath -Value "***********************************************************************"
                        Write-Host "**********************************************************************************************************"
                        continue
                    }
            } 
        }
    }
}
