#####################################################################
# PRIME Package Editor
#####################################################################
# Release History:
#   V0.1 - Initial Release
#   V0.2 - Update to handle multiple manifest files
#####################################################################

#Backup original XML files
Write-Host "Backing up package XML files" -ForegroundColor DarkGreen
If ((Test-Path "./Original" -PathType Container) -ne $true)
{
    #only back up another if we havet done this before (prevents overwriting with modified entries)
    MD "./Original" -Force
    Copy "*.xml" "./Original/" -Force
}
#Create working copy of XML files
MD "./Data" -Force
Copy "*.xml" "./Data/" -Force

$sourcepath = Get-Location
$workingpath = "$sourcepath\Data"

#####################################################################
# Open SystemData.xml
##################
[System.Xml.XmlDocument]$SystemDataXML = Get-Content -Path "$workingpath\SystemData.xml"
Write-Host "Editing SystemData.xml" -ForegroundColor DarkGreen

# Update Package Version
Write-Host "Package Version: " $SystemDataXML.SystemData.SchemaVersion.Version
$SystemDataXML.SystemData.SchemaVersion.Version = "15.0.0.0"
Write-Host "Updated Package Version: " $SystemDataXML.SystemData.SchemaVersion.Version

# Update SystemObjects
##Nothing yet

$SystemDataXML.Save("$workingpath\SystemData.xml")
##################
# Close SystemData.xml
#####################################################################

#####################################################################
# Open Manifest.xml
##################
ForEach($ManifestFileName In Get-ChildItem -Path $workingpath -Name "Manifest*.xml")
{
    Write-Host "Editing $ManifestFileName" -ForegroundColor DarkGreen

    [System.Xml.XmlDocument]$ManifestXML = Get-Content -Path "$workingpath\$ManifestFileName"

    # Update Feature SPObjects
    $ManifestXML.SPObjects.SPObject | ?{$_.ObjectType -eq "SPFeature"} | %{$_.Feature}|ForEach-Object -Process {
        Write-Host ("Feature: {0}, {1}, {2}, {3}, {4}" -f $_.Id, $_.FeatureDefinitionName, $_.Version, $_.IsUserSolutionFeature, $_.FeatureDefinitionScope)
        
        #Add FeatureDefinitionScope
        If($_.IsUserSolutionFeature -eq $true)
        {
            $_.SetAttribute("FeatureDefinitionScope", "2")
        }
        else
        {
            $_.SetAttribute("FeatureDefinitionScope", "1")
        }

        Write-Host "Added FeatureDefinitionScope value"
    }

    $ManifestXML.Save("$workingpath\$ManifestFileName")
}
##################
# Close Manifest.xml
#####################################################################

#####################################################################
# Open Requirements.xml
##################
[System.Xml.XmlDocument]$RequirementsXML = Get-Content -Path "$workingpath\Requirements.xml"
Write-Host "Editing Requirements.xml" -ForegroundColor DarkGreen

# Remove Features
$RequirementsXML.Requirements.Requirement  | ?{$_.Type -eq "FeatureDefinition"} | ForEach-Object -Process {
    $KnownGoodFeatures = [array]"Fields"
        , "CTypes"
    $BadFeatures = [array]"MobileWordViewer", "MobilePowerPointViewer", "PowerPointServer", "PowerPointEditServer", "ExcelServerEdit"
        , "ReportServer"
        , "WAReports", "WAMaster", "WAWhatsPopularWebPart", "WACustomReports"
        , "SubWebEventReceiver", "SiteInfoCollection", "SiteInfoCustom", "SiteInfoCustomActions", "SiteControlsRegistration", "SiteDeletionHistory", "SiteInfoContentTypes", "SiteInfractionPage"
    If ($BadFeatures -contains $_.Name)
    {
        write-host "Removing Bad Feature Dependency: ", $_.Name.ToString() -ForegroundColor DarkYellow
        $Parent = $_.ParentNode
        $Parent.RemoveChild($_)
    }
}

$RequirementsXML.Save("$workingpath\Requirements.xml")

##################
# Close Requirements.xml
#####################################################################

#####################################################################
# Open UserGroup.xml
##################
[System.Xml.XmlDocument]$UserGroupXML = Get-Content -Path "$workingpath\UserGroup.xml"
Write-Host "Editing UserGroup.xml" -ForegroundColor DarkGreen

# Iterate through all users
$UserGroupXML.UserGroupMap.Users.User | ForEach-Object -Process {
    # Update Login
    Write-Host ("User: {0}, {1}, {2}, {3}, {4}" -f $_.Id, $_.Name, $_.Login, $_.Email, $_.IsDeleted)

    $Login = $_.Login
    $Name = $_.Name
    
    Switch($Login)
    {
        "All Authenticated Users"
        {
            $Login = "c:0(.s|true"
            $Name = "All Authenticated Users"
        }
        "NT AUTHORITY\authenticated users"
        {
            $Login = "c:0-.f|rolemanager|spo-grid-all-users/ec63b09b-9748-47ba-9018-beeadd405204"
            $Name = "All Users (membership)"
            #"c:0!.s|windows"
        }
        "SharePoint\System"
        {
            #Do nothing to login, leave it as is

        }
        default
        {
            $LoginParts=$Login.Split("\")
            If ($LoginParts.Count -gt 1)
            {
                $Login = "i:0#.f|membership|" + $LoginParts[1] + "@microsoft.com"
            }
        }
    }
    $_.Login = $Login
    Write-Host "Updated Login: " $_.Login
}

$UserGroupXML.Save("$workingpath\UserGroup.xml")
##################
# Close UserGroup.xml
#####################################################################
