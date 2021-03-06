#####################################################################
# PRIME Migration Commands
#####################################################################
# Release History:
#   V1.0 - Initial Release
#   V1.1 - Fixed default export file sizing bug, logging file overwrite issues, and now also writes the changetoken value into a file in the output folder or folder of the output file
#####################################################################

#Setting StrictMode to ensure code is well built and works correctly
Set-StrictMode -Version 2.0 

#Load Microsoft.SharePoint.PowerShell snapins if they are not loaded
If(Get-PSSnapin Microsoft.SharePoint.PowerShell -Registered)
{
    Write-Debug "SharePoint Snapin Registered";
    If(Get-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)
    {
        Write-Debug "SharePoint Snapin Already Loaded"
    }
    Else
    {
        Add-PSSnapin Microsoft.SharePoint.PowerShell; Write-Debug "SharePoint Snapin Loaded"
    }
}
Else
{
    Write-Error "SharePoint Snapin Not Registered"
}

#*******************************************************************
# Functions
#*******************************************************************
function Import-SPSite
{

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPSite')]
        [Microsoft.SharePoint.PowerShell.SPSitePipeBind] $Identity,
        [Parameter(Mandatory = $false)]
        [String] $Path,
        [Parameter(Mandatory = $false)]
        [Switch] $NoFileCompression = $true,
        [Parameter(Mandatory = $false)]
        [Switch] $ForceOverwrite = $false,
        [Parameter(Mandatory = $false)]
        [Switch] $RetainObjectIdentity = $true,
        [Parameter(Mandatory = $false)]
        [Switch] $ActivateSolutions = $true,
        [Parameter(Mandatory = $false)]
        [Switch] $IncludeUserSecurity = $true,
        [Parameter(Mandatory = $false)]
        [Switch] $NoLogFile = $false,
        [Parameter(Mandatory = $false)]
        [Switch] $HaltOnError = $false,
        [Parameter(Mandatory = $false)]
        [Switch] $HaltOnWarning = $false,
        [Parameter(Mandatory = $false)]
        [Microsoft.SharePoint.Deployment.SPIncludeUserCustomAction] $IncludeUserCustomAction = [Microsoft.SharePoint.Deployment.SPIncludeUserCustomAction]::All,
        [Parameter(Mandatory = $false)]
        [Microsoft.SharePoint.Deployment.SPUpdateVersions] $UpdateVersions = [Microsoft.SharePoint.Deployment.SPUpdateVersions]::Overwrite
    )
    begin
    {
        [Microsoft.SharePoint.Deployment.SPIncludeUserCustomAction] $m_IncludeUserCustomAction = $IncludeUserCustomAction;
        [Microsoft.SharePoint.Deployment.SPUpdateVersions] $m_UpdateVersions = $UpdateVersions;
        [bool] $m_RetainObjectIdentity = $RetainObjectIdentity;
        [bool] $m_IncludeUserSecurity = $IncludeUserSecurity;
        [bool] $m_ActivateSolutions = $ActivateSolutions;
        [bool] $m_FileCompression = !$NoFileCompression;
        [bool] $m_ForceOverwrite = $ForceOverwrite;
        [bool] $m_HaltOnWarning = $HaltOnWarning;
        [bool] $m_HaltOnError = $HaltOnError;
        [bool] $m_NoLogFile = $NoLogFile;
        [String] $m_logFile = "import.log";

        [bool] $m_Verbose = $false;
        if($PSCmdlet.MyInvocation.BoundParameters["Verbose"] -ne $Null)
        {
            $m_Verbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"];
        }
    }
    process
    {
        [Microsoft.SharePoint.Deployment.SPImportSettings] $importSettings = New-Object Microsoft.SharePoint.Deployment.SPImportSettings;
        [Microsoft.SharePoint.Deployment.SPImport] $import = New-Object Microsoft.SharePoint.Deployment.SPImport($importSettings);

        [String] $m_path = "";
        [String] $m_filename = "";
        if ($m_FileCompression)
        {
            #Split the filename/directory name
            SplitPathFile -FullFilePath $Path -Path ([Ref] $m_path) -FileName ([Ref] $m_filename);
            $importSettings.FileLocation = $m_path;
            $importSettings.BaseFileName = $m_filename;
        }
        else
        {
            $importSettings.FileLocation = $m_path = $Path;
        }

        if (!$m_NoLogFile)
        {
            if($m_filename -ne [String]::Empty)
            {
                $importSettings.LogFilePath = [System.IO.Path]::Combine($importSettings.FileLocation, $m_filename + "." + $m_logFile);
            }
            else
            {
                $importSettings.LogFilePath = [System.IO.Path]::Combine($importSettings.FileLocation, $m_logFile);
            }
            
            if (Test-Path -Path $importSettings.LogFilePath -PathType Leaf)
            {
                if ($m_ForceOverwrite)
                {
                    #delete existing log
                    Remove-Item -Path $importSettings.LogFilePath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        [Microsoft.SharePoint.SPSite] $Site = $Identity.Read();
        [String] $m_url = $Site.Url;
        if ($m_url[$m_url.Length - 1] -eq '/')
        {
            $m_url = $m_url.TrimEnd({ '/' });
        }
            
        $importSettings.CommandLineVerbose = $m_Verbose;
        $importSettings.HaltOnNonfatalError = $m_HaltOnError;
        $importSettings.HaltOnWarning = $m_HaltOnWarning;
        #$importSettings.WarnOnUsingLastMajor = $true;
        $importSettings.FileCompression = $m_FileCompression;

        if ($m_IncludeUserSecurity)
        {
            $importSettings.IncludeSecurity = [Microsoft.SharePoint.Deployment.SPIncludeSecurity]::All;
            $importSettings.UserInfoDateTime = [Microsoft.SharePoint.Deployment.SPImportUserInfoDateTimeOption]::ImportAll;
        }

        $importSettings.UpdateVersions = $m_UpdateVersions;
        $importSettings.IncludeUserCustomAction = $m_IncludeUserCustomAction;
        $importSettings.ActivateSolutions = $m_ActivateSolutions;
        $importSettings.RetainObjectIdentity = $m_RetainObjectIdentity;
        $importSettings.SiteUrl = $m_url;

        $import.Run();
    }
}

function Export-SPSite
{

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPSite')]
        [Microsoft.SharePoint.PowerShell.SPSitePipeBind] $Identity,
        [Parameter(Mandatory = $true)]
        [String] $Path,
        [Parameter(Mandatory = $false)]
        [Switch] $NoFileCompression = $true,
        [Parameter(Mandatory = $false)]
        [Switch] $GetChangeToken = $true,
        [Parameter(Mandatory = $false)]
        [String] $ChangeToken,
        [Parameter(Mandatory = $false)]
        [int] $CompressionSize = 24,
        [Parameter(Mandatory = $false)]
        [Switch] $UseSqlSnapshot = $false,
        [Parameter(Mandatory = $false)]
        [Switch] $ForceOverwrite = $false,
        [Parameter(Mandatory = $false)]
        [Switch] $IncludeUserSecurity = $true,
        [Parameter(Mandatory = $false)]
        [Switch] $NoLogFile = $false,
        [Parameter(Mandatory = $false)]
        [Switch] $HaltOnError = $false,
        [Parameter(Mandatory = $false)]
        [Switch] $HaltOnWarning = $false,
        [Parameter(Mandatory = $false)]
        [Microsoft.SharePoint.Deployment.SPIncludeUserCustomAction] $IncludeUserCustomAction = [Microsoft.SharePoint.Deployment.SPIncludeUserCustomAction]::All,
        [Parameter(Mandatory = $false)]
        [Microsoft.SharePoint.Deployment.SPIncludeVersions] $IncludeVersions = [Microsoft.SharePoint.Deployment.SPIncludeVersions]::All
    )
    begin
    {
        [Microsoft.SharePoint.Deployment.SPIncludeVersions] $m_IncludeVersions = $IncludeVersions;
        [bool] $m_IncludeUserSecurity = $IncludeUserSecurity;
        [bool] $m_ForceOverwrite = $ForceOverwrite;
        [bool] $m_HaltOnWarning = $HaltOnWarning;
        [bool] $m_HaltOnError = $HaltOnError;
        [bool] $m_FileCompression = !$NoFileCompression;
        [bool] $m_NoLogFile = $NoLogFile;
        [String] $m_logFile = "export.log";
        [bool] $m_GetChangeToken = $GetChangeToken;
        [String] $m_ChangeToken = $ChangeToken;
        [int] $m_CompressionSize = $CompressionSize

        [bool] $m_Verbose = $false 
        if($PSCmdlet.MyInvocation.BoundParameters["Verbose"] -ne $Null)
        {
            $m_Verbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"];
        }
    }
    process
    {
        [Microsoft.SharePoint.Deployment.SPExportSettings] $exportSettings = New-Object Microsoft.SharePoint.Deployment.SPExportSettings;
        [Microsoft.SharePoint.Deployment.SPExport] $export = New-Object Microsoft.SharePoint.Deployment.SPExport($exportSettings);

        [String] $m_path = "";
        [String] $m_filename = "";
        if ($m_FileCompression)
        {
            #Split the filename/directory name
            SplitPathFile -FullFilePath $Path -Path ([Ref]$m_path) -FileName ([Ref]$m_filename);
            $exportSettings.FileLocation = $m_path;
            $exportSettings.BaseFileName = $m_filename;
            if ($m_ForceOverwrite)
            {
                #delete existing export folder
                Remove-Item -Path ([System.IO.Path]::Combine($exportSettings.FileLocation, $m_filename + "*.cmp")) -Recurse -Force
            }
        }
        else
        {
            $exportSettings.FileLocation = $m_path = $Path;
            if ($m_ForceOverwrite)
            {
                #delete existing export folder
                Remove-Item -Path $m_path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if (!$m_NoLogFile)
        {
        
            if($m_filename -ne [String]::Empty)
            {
                $exportSettings.LogFilePath = [System.IO.Path]::Combine($exportSettings.FileLocation, $m_filename + "." + $m_logFile);
            }
            else
            {
                $exportSettings.LogFilePath = [System.IO.Path]::Combine($exportSettings.FileLocation, $m_logFile);
            }
            
            if (Test-Path -Path $exportSettings.LogFilePath -PathType Leaf)
            {
                if ($m_ForceOverwrite)
                {
                    #delete existing log
                    Remove-Item -Path $exportSettings.LogFilePath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        [Microsoft.SharePoint.SPSite] $Site = $Identity.Read();
        [String] $m_url = $Site.Url;
        if ($m_url[$m_url.Length - 1] -eq '/')
        {
            $m_url = $m_url.TrimEnd({ '/' });
        }
        
        if (!$UseSqlSnapshot)
        {
            if (!$Site.ContentDatabase.IsAttachedToFarm)
            {
                $exportSettings.UnattachedContentDatabase = $Site.ContentDatabase;
            }
            $exportSettings.SiteUrl = $m_url;
        }
        else
        {
            $database = $Site.ContentDatabase;
            $snapshot = $database.Snapshots.CreateSnapshot();

            [Microsoft.SharePoint.SPContentDatabase] $unattached =
                [Microsoft.SharePoint.SPContentDatabase]::CreateUnattachedContentDatabase($snapshot.ConnectionString);

            $exportSettings.UnattachedContentDatabase = $unattached;
            $exportSettings.SiteUrl = $unattached.Sites[$Site.ServerRelativeUrl].Url;
        }

        [Microsoft.SharePoint.Deployment.SPExportObject] $exportObject = New-Object Microsoft.SharePoint.Deployment.SPExportObject;
        $exportObject.ExcludeChildren = $false;
        $exportObject.Id = $Site.Id; #should this be $Site.RootWeb.Id ??
        $exportObject.Type = [Microsoft.SharePoint.Deployment.SPDeploymentObjectType]::Site;
        $exportObject.Url = $Site.ServerRelativeUrl;
        $exportSettings.ExportObjects.Add($exportObject);
        
        $exportSettings.ExportMethod = [Microsoft.SharePoint.Deployment.SPExportMethodType]::ExportAll;
        $exportSettings.ExcludeDependencies = $true;        
        $exportSettings.CommandLineVerbose = $m_Verbose;
        $exportSettings.HaltOnNonfatalError = $m_HaltOnError;
        $exportSettings.HaltOnWarning = $m_HaltOnWarning;
        $exportSettings.FileCompression = $m_FileCompression;
        $exportSettings.OverwriteExistingDataFile = $m_ForceOverwrite;
        $exportSettings.FileMaxSize = $m_CompressionSize; <# Note that this sets not only the intended output CAB file size but also the maximum Manifest XMl size (due to the quirk in CAB files where it can not span files across multiple CAB files, so setting the maximum manifest.xml size helps to keep to that size unless actual file stream content exceeds the setting) #>
        
        if (!([String]::IsNullOrEmpty($m_ChangeToken)))
        {
            Write-Host "Starting Export From Change Token: " $m_ChangeToken;
            $exportSettings.ExportMethod = [Microsoft.SharePoint.Deployment.SPExportMethodType]::ExportChanges;
            $exportSettings.ExportChangeToken = $m_ChangeToken;
        }

        if ($m_IncludeUserSecurity)
        {
            $exportSettings.IncludeSecurity = [Microsoft.SharePoint.Deployment.SPIncludeSecurity]::All;
        }

        $exportSettings.IncludeVersions = $m_IncludeVersions;
        $export.Run();
        if($m_GetChangeToken)
        {
            Write-Host "Export Change Token: "$exportSettings.ExportChangeToken
            Write-Host "Current Change Token: "$exportSettings.CurrentChangeToken
            if($m_filename -ne [String]::Empty)
            {
                $m_ChangeTokenFile = [System.IO.Path]::Combine($exportSettings.FileLocation, $m_filename +"." + [DateTime]::Now.Ticks + ".ChangeTokens.txt");
            }
            else
            {
                $m_ChangeTokenFile = [System.IO.Path]::Combine($exportSettings.FileLocation, "Export." + [DateTime]::Now.Ticks + ".ChangeTokens.txt");
            }
            Write-Output ("ExportChangeToken=""" + $exportSettings.ExportChangeToken + """, CurrentChangeToken=""" + $exportSettings.CurrentChangeToken + """") > $m_ChangeTokenFile
        }
    }
}

function SplitPathFile(
    [Parameter(Mandatory = $true)] [String] $FullFilePath,
    [Parameter(Mandatory = $true)] [Ref] $Path,
    [Parameter(Mandatory = $true)] [Ref] $FileName
    )
{
    [System.IO.FileInfo] $m_fileInfo = New-Object System.IO.FileInfo($FullFilePath);

    # Powershell does not change System.Environment.CurrentDirectory
    # when changing between directories from the command line.
    # This causes us to use c:\windows\system32 as the default
    # directory instead of the current one.
    if ($m_fileInfo.Name -eq $FullFilePath)
    {
        $m_fileInfo = New-Object System.FileInfo(
            [System.IO.Path]::Combine(
                $SessionState.Path.CurrentLocation.Path,
                $FullFilePath));
    }

    $Path.Value = $m_fileInfo.Directory.FullName;
    $FileName.Value = $m_fileInfo.Name;
}

function GetServerRelUrlFromFullUrl([Parameter(Mandatory = $true)] [String] $Url)
{
    [String] $m_ServerRelUrl;
    [Int] $i_DoubleSlash = $Url.IndexOf("//");
    if ($i_DoubleSlash -lt 0 -or $i_DoubleSlash -eq $Url.Length - 2) # found "//" at the end of string
    {
        #throw new ArgumentNullException("Url");
    }

    [Int] $i_Slash = $Url.IndexOf('/', $i_DoubleSlash + 2);
    if ($i_Slash -lt 0)
    {
        $m_ServerRelUrl = "/";
    }
    else
    {
        $m_ServerRelUrl = $Url.Substring($i_Slash);
        if ($m_ServerRelUrl.Length -gt 1 -and $m_ServerRelUrl[$m_ServerRelUrl.Length - 1] -eq '/')
        {
            $m_ServerRelUrl = $m_ServerRelUrl.Substring(0, $m_ServerRelUrl.Length - 1);
        }
    }
    return $m_ServerRelUrl;
}