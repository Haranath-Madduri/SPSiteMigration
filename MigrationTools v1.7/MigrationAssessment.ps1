#####################################################################
# Migration Assessment Tools
#####################################################################
# Release History:
#   V1.0 - Initial Release
#   V1.1 - Update to add more detail of items gathered
#   V1.2 - Update for various bugs fixes including flagging readlocked sites
#   V1.3 - Update fixing couple more bugs and adding gathersession, site, and web Ids on elements for database import
#   V1.4 - Update fixing couple more bugs, fixed groups output, changed MigrationXMLdocument routine, changed a few property names, and added more new properties
#   V1.5 - Update fixing couple more error handling bugs, and added new output ability when using XML nodes (controlled by global variables included in this script)
#   V1.6 - Update fixing couple more error handling bugs, user, event reciever, workflow and nav gathering. Also causes a new WorkflowAssociations node at Web level when applicable and WorkflowAssociationsCount at Web level. Added ScriptVersion tracking value in each gather object, and there are a couple changes in user and eventreceiver node attributes structure
#   V1.7 - Update fixed forgroundcolor issue on messages, missing groups, missing navigation node children, added UseShared and three count values to the Navigationobject, Home node to the Navigation object, and added the five usage tracking values to the Site object
#####################################################################


#*******************************************************************
# Script Global Variables
#*******************************************************************
$script:Version = "1.7"
$script:IncludeNodeParenting = $true    #use this to control including the parent tracking information for database import
$script:DisplayXMLNodeOutput = $true    #use this to control showing each XML node in the output
$script:NoNewLineOnXMLAttributes = $false    #use this to control including a newline for each XML attribute in the output
$script:GatherSessionId = $null
$script:SiteId = $null
$script:WebId = $null

#*******************************************************************
# Snapin Utility Functions
#*******************************************************************

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
# XML Utility Functions
#*******************************************************************

function Add-XMLElement
{
    [CmdletBinding()]
    param([System.Xml.XmlElement]$ParentNode, [string]$name, [string]$value)
    trap [Exception]
    { 
        Write-Host "Error when writing value for $name :"
        Write-Host "$($_.Exception.GetType().FullName) : $($_.Exception.Message)"
        break 
    }
    
    If($script:DisplayXMLNodeOutput)
    {
        Write-Host ""
        Write-Host "$name"
        If([String]::IsNullOrEmpty($value) -ne $true)
        {
            Write-Host "$value"
        }
    }

    $ElementNode = $xml.CreateElement($name) 
    if(($value -ne $NULL) -and ($value -ne ''))
    {
        $ElementNode.set_InnerText($value)
    }
    else
    {
        $ElementNode.IsEmpty = $True
    }
    If($script:IncludeNodeParenting)
    {
        If($script:GatherSessionId -ne $null)
        {
            $ElementNode.SetAttribute("GatherSession_Id", $script:GatherSessionId)
        }
        Else
        {
            $ElementNode.SetAttribute("GatherSession_Id", "")
        }

        If($script:GatherSessionId -ne $null)
        {
            $ElementNode.SetAttribute("Gather_Site_Id", $script:SiteId)
        }
        Else
        {
            $ElementNode.SetAttribute("Gather_Site_Id", "")
        }

        If($script:GatherSessionId -ne $null)
        {
            $ElementNode.SetAttribute("Gather_Web_Id", $script:WebId)
        }
        Else
        {
            $ElementNode.SetAttribute("Gather_Web_Id", "")
        }
    }
    $ParentNode.AppendChild($ElementNode)
}


function Add-XMLAttribute
{
    [CmdletBinding()]
    param([System.Xml.XmlElement]$ElementNode, [string]$name, [string]$value)
    trap [Exception] 
    {
        Write-Host "Error when writing value for $name : "
        Write-Host "$($_.Exception.GetType().FullName) : $($_.Exception.Message)"
        break 
    }

    If($script:DisplayXMLNodeOutput)
    {
        Write-Host "[$name = $value]" -NoNewline:$script:NoNewLineOnXMLAttributes
    }

    if($name -ne $null)
    {
        if($value -ne $null)
        {
            $ElementNode.SetAttribute($name, $value) 
        }
        else
        {
            $ElementNode.SetAttribute($name, "") 
        }
    }
}

#*******************************************************************
# Gathering Utility Routines
#*******************************************************************

#Create XML structure for gathering session
function Set-SPMigrationXMLOutputDocument
{
    #setup xml document structure
    $xmldoc = New-Object "System.Xml.XmlDocument"
    $XMLDocumentDeclaration = $xmldoc.CreateXmlDeclaration("1.0", $null, $null)
    $xmldoc.AppendChild($XMLDocumentDeclaration) | Out-Null

    #create root document element
    $GatherRootXMLElement = $xmldoc.CreateElement("GatherSession")
    $xmldoc.AppendChild($GatherRootXMLElement) | Out-Null

    #reset script variables
    $script:GatherSessionId = ([System.Guid]::NewGuid().ToString())
    $script:SiteId = $null
    $script:WebId = $null
    
    #add run details
    Add-XMLAttribute $GatherRootXMLElement "Id" $script:GatherSessionId
    Add-XMLAttribute $GatherRootXMLElement "Date" (Get-Date)
    Add-XMLAttribute $GatherRootXMLElement "RunFrom" (Get-Content env:computername)
    Add-XMLAttribute $GatherRootXMLElement "ScriptVersion" $script:Version
    return $xmldoc
}

#Load Sites List From Text File
function Get-SPSitesFromText([string] $FileName)
{
    If(Test-Path $FileName)
    {
        [String[]]$Sites = Get-Content $FileName
        $Sites | %{Get-SPSite $_ -ErrorVariable Err -ErrorAction SilentlyContinue; If($Err){Write-Host "Error: $Err" -ForegroundColor ([System.ConsoleColor]::Red)}}
    }
}

#*******************************************************************
# Gathering Routines
#*******************************************************************

#Get migration related data from a passed in SPSite
function Get-SPSiteMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPSite')]
        [Microsoft.SharePoint.SPSite]$Site,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($Site -eq $null)
        {
            Write-Host "Null Site Encountered" -ForegroundColor ([System.ConsoleColor]::Red)
        }
        else
        {
            If($ParentXMLNode -ne $null)
            {
                $script:SiteId = $Site.Id.Guid
                $script:WebId = $null

                $SiteXMLElement = Add-XMLElement $ParentXMLNode "Site"
            }

            $NoAccess = $false
            $NoAdditions = $false

            If ($Site.WriteLocked -eq $null -or $Site.WriteLocked -eq $true)
            {
                if ($Site.ReadLocked -eq $null -or $Site.ReadLocked -eq $true)
                {
                    $NoAccess = $true
                    $NoAdditions = $false
                }
                else
                {
                    $NoAccess = $false
                    $NoAdditions = $true
                }
            }

            If(!$HideOutput.ToBool())
            {
                Write-Host "Beginning Site: $Site.Id.Guid ($Site.Url)"
                Write-Host $Site.Id.Guid,
                    $Site.Url,
                    $Site.Owner.Id,
                    $Site.Owner.UserLogin,
                    $Site.Owner.Email,
                    $Site.SecondaryContact.Id,
                    $Site.SecondaryContact.UserLogin,
                    $Site.SecondaryContact.Email,
                    $NoAccess,
                    $NoAdditions,
                    $Site.ReadOnly,
                    $Site.ReadLocked,
                    $Site.WriteLocked,
                    $Site.HostHeaderIsSiteName,
                    $Site.LastContentModifiedDate,
                    $Site.LastSecurityModifiedDate,
                    $Site.CertificationDate,
                    $Site.AllowDesigner,
                    $Site.AllowMasterPageEditing,
                    $Site.AllowRevertFromTemplate,
                    $Site.AllowRssFeeds,
                    $Site.AllowUnsafeUpdates,
                    $Site.BrowserDocumentsEnabled,
                    $Site.SyndicationEnabled,
                    $Site.UIVersionConfigurationEnabled,
                    $Site.UserCodeEnabled,
                    $Site.ContentDatabase.Name,
                    $Site.Quota.QuotaId,
                    $Site.Quota.StorageWarningLevel,
                    $Site.Quota.StorageMaximumLevel,
                    $Site.Quota.InvitedUserMaximumLevel,
                    $Site.Quota.UserCodeWarningLevel,
                    $Site.Quota.UserCodeMaximumLevel,
                    $Site.Usage.Storage,
                    $Site.Usage.DiscussionStorage,
                    $Site.Usage.Visits,
                    $Site.Usage.Hits,
                    $Site.Usage.Bandwidth,
                    $Site.RootWeb.SiteAdministrators.Count,
                    $Site.RootWeb.SiteUsers.Count,
                    $Site.RootWeb.SiteGroups.Count,
                    $Site.Solutions.Count,
                    $Site.Solutions.Count,
                    $Site.Features.Count,
                    $Site.UserCustomActions.Count,
                    $Site.EventReceivers.Count
            }
        
            If($SiteXMLElement -ne $null)
            {
                Add-XMLAttribute $SiteXMLElement "Id" $Site.Id.Guid
                Add-XMLAttribute $SiteXMLElement "Url" $Site.Url
                Add-XMLAttribute $SiteXMLElement "Owner_Id" $Site.Owner.Id
                Add-XMLAttribute $SiteXMLElement "Owner_UserLogin" $Site.Owner.UserLogin
                Add-XMLAttribute $SiteXMLElement "Owner_Email" $Site.Owner.Email
                Add-XMLAttribute $SiteXMLElement "SecondaryContact_Id" $Site.SecondaryContact.Id
                Add-XMLAttribute $SiteXMLElement "SecondaryContact_UserLogin" $Site.SecondaryContact.UserLogin
                Add-XMLAttribute $SiteXMLElement "SecondaryContact_Email" $Site.SecondaryContact.Email
                Add-XMLAttribute $SiteXMLElement "NoAccess" $NoAccess
                Add-XMLAttribute $SiteXMLElement "NoAdditions" $NoAdditions
                Add-XMLAttribute $SiteXMLElement "ReadOnly" $Site.ReadOnly
                Add-XMLAttribute $SiteXMLElement "ReadLocked" $Site.ReadLocked
                Add-XMLAttribute $SiteXMLElement "WriteLocked" $Site.WriteLocked
                Add-XMLAttribute $SiteXMLElement "HostHeaderIsSiteName" $Site.HostHeaderIsSiteName
                Add-XMLAttribute $SiteXMLElement "LastContentModifiedDate" $Site.LastContentModifiedDate
                Add-XMLAttribute $SiteXMLElement "LastSecurityModifiedDate" $Site.LastSecurityModifiedDate
                Add-XMLAttribute $SiteXMLElement "CertificationDate" $Site.CertificationDate
                Add-XMLAttribute $SiteXMLElement "AllowDesigner" $Site.AllowDesigner
                Add-XMLAttribute $SiteXMLElement "AllowMasterPageEditing" $Site.AllowMasterPageEditing
                Add-XMLAttribute $SiteXMLElement "AllowRevertFromTemplate" $Site.AllowRevertFromTemplate
                Add-XMLAttribute $SiteXMLElement "AllowRssFeeds" $Site.AllowRssFeeds
                Add-XMLAttribute $SiteXMLElement "AllowUnsafeUpdates" $Site.AllowUnsafeUpdates
                Add-XMLAttribute $SiteXMLElement "BrowserDocumentsEnabled" $Site.BrowserDocumentsEnabled
                Add-XMLAttribute $SiteXMLElement "SyndicationEnabled" $Site.SyndicationEnabled
                Add-XMLAttribute $SiteXMLElement "UIVersionConfigurationEnabled" $Site.UIVersionConfigurationEnabled
                Add-XMLAttribute $SiteXMLElement "UserCodeEnabled" $Site.UserCodeEnabled
                Add-XMLAttribute $SiteXMLElement "ContentDatabase" $Site.ContentDatabase.Name
                Add-XMLAttribute $SiteXMLElement "Quota_Id" $Site.Quota.QuotaId
                Add-XMLAttribute $SiteXMLElement "Quota_StorageWarningLevel" $Site.Quota.StorageWarningLevel
                Add-XMLAttribute $SiteXMLElement "Quota_StorageMaximumLevel" $Site.Quota.StorageMaximumLevel
                Add-XMLAttribute $SiteXMLElement "Quota_InvitedUserMaximumLevel" $Site.Quota.InvitedUserMaximumLevel
                Add-XMLAttribute $SiteXMLElement "Quota_UserCodeWarningLevel" $Site.Quota.UserCodeWarningLevel
                Add-XMLAttribute $SiteXMLElement "Quota_UserCodeMaximumLevel" $Site.Quota.UserCodeMaximumLevel
                Add-XMLAttribute $SiteXMLElement "Usage_Storage" $Site.Usage.Storage
                Add-XMLAttribute $SiteXMLElement "Usage_DiscussionStorage" $Site.Usage.DiscussionStorage
                Add-XMLAttribute $SiteXMLElement "Usage_Visits" $Site.Usage.Visits
                Add-XMLAttribute $SiteXMLElement "Usage_Hits" $Site.Usage.Hits
                Add-XMLAttribute $SiteXMLElement "Usage_Bandwidth" $Site.Usage.Bandwidth
                Add-XMLAttribute $SiteXMLElement "PortalName" $Site.PortalName
                Add-XMLAttribute $SiteXMLElement "PortalUrl" $Site.PortalUrl
                Add-XMLAttribute $SiteXMLElement "SiteAdministratorsCount" $Site.RootWeb.SiteAdministrators.Count
                Add-XMLAttribute $SiteXMLElement "SiteUsersCount" $Site.RootWeb.SiteUsers.Count
                Add-XMLAttribute $SiteXMLElement "SiteGroupsCount" $Site.RootWeb.SiteGroups.Count
                Add-XMLAttribute $SiteXMLElement "SolutionsCount" $Site.Solutions.Count
                Add-XMLAttribute $SiteXMLElement "FeaturesCount" $Site.Features.Count
                Add-XMLAttribute $SiteXMLElement "UserCustomActionsCount" $Site.UserCustomActions.Count
                Add-XMLAttribute $SiteXMLElement "EventReceiversCount" $Site.EventReceivers.Count
            }
            If ($Site.ReadLocked -ne $false)
            {
                #this site collection is not readable, so do nothing further for it or its children
                Write-Host "Error: Site Collection $Site.Url is read locked" -ForegroundColor ([System.ConsoleColor]::DarkYellow)
            }
            else
            {
                #List Site Administrators
                If($SiteXMLElement -ne $null)
                {
                    $SiteAdminsXMLElement = Add-XMLElement $SiteXMLElement "SiteAdministrators"
                }
                ForEach($SiteAdmin In $Site.RootWeb.SiteAdministrators)
                {
                    If($SiteAdmin -ne $null)
                    {
                        Get-SPUserMigrationData $SiteAdmin $SiteAdminsXMLElement -HideOutput:$HideOutput
                    }
                }

                #List Site Users
                If($SiteXMLElement -ne $null)
                {
                    $SiteUsersXMLElement = Add-XMLElement $SiteXMLElement "SiteUsers"
                }
                ForEach($SiteUser In $Site.RootWeb.SiteUsers)
                {
                    If($SiteUser -ne $null)
                    {
                        Get-SPUserMigrationData $SiteUser $SiteUsersXMLElement -HideOutput:$HideOutput
                    }
                }

                #List Site Groups
                If($SiteXMLElement -ne $null)
                {
                    $SiteGroupsXMLElement = Add-XMLElement $SiteXMLElement "SiteGroups"
                }
                ForEach($SiteGroup In $Site.RootWeb.SiteGroups)
                {
                    If($SiteGroup -ne $null)
                    {
                        Get-SPGroupMigrationData $SiteGroup $SiteGroupsXMLElement -HideOutput:$HideOutput
                    }
                }

                #List Site Solutions
                If($Site.Solutions.Count -gt 0)
                {
                    Get-SPUserSolutionCollectionMigrationData $Site.Solutions $SiteXMLElement -HideOutput:$HideOutput
                }
            
                #List Site Features
                If($Site.Features.Count -gt 0)
                {
                    Get-SPFeatureCollectionMigrationData $Site.Features $SiteXMLElement -HideOutput:$HideOutput
                }
            
                #List Site UserCustomActions
                If($Site.UserCustomActions.Count -gt 0)
                {
                    Get-SPUserCustomActionCollectionMigrationData $Site.UserCustomActions $SiteXMLElement -HideOutput:$HideOutput
                }
            
                #List Site EventReceivers
                If($Site.EventReceivers.Count -gt 0)
                {
                    Get-SPEventReceiverDefinitionCollectionMigrationData $Site.EventReceivers $SiteXMLElement -HideOutput:$HideOutput
                }
            
                #List data for all webs in site
                Get-SPWebCollectionMigrationData $Site.AllWebs $SiteXMLElement -HideOutput:$HideOutput
            }
        }
    }
}

#Get migration related data from a passed in SPWebCollection
function Get-SPWebCollectionMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPWebCollection')]
        [Microsoft.SharePoint.SPWebCollection]$Webs,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $script:WebId = $null
            $WebsXMLElement = Add-XMLElement $ParentXMLNode "Webs"
        }

        ForEach($Web In $Webs)
        {        
            If($Web -ne $null)
            {
                Get-SPWebMigrationData $Web $WebsXMLElement -HideOutput:$HideOutput
            }
        }
    }
}

#Get migration related data from a passed in SPWeb
function Get-SPWebMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPWeb')]
        [Microsoft.SharePoint.SPWeb]$Web,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($Web -eq $null)
        {
            Write-Host "Error: Null Web Encountered" -ForegroundColor ([System.ConsoleColor]::DarkYellow)
        }
        else
        {
            If($ParentXMLNode -ne $null)
            {
                $script:WebId = $Web.Id.Guid
                $WebXMLElement = Add-XMLElement $ParentXMLNode "Web"
            }

            If(!$HideOutput.ToBool())
            {
                Write-Host "Beginning Web: $Web.Id.Guid ($Web.Url)"
                Write-Host $Web.Id.Guid,
                    $Web.ParentWebId.Guid,
                    $Web.Url,
                    $Web.WebTemplateId,
                    $Web.WebTemplate,
                    $Web.Configuration,
                    $Web.Title,
                    $Web.Language,
                    $Web.UIVersion,
                    $Web.UIVersionConfigurationEnabled,
                    $Web.LastItemModifiedDate,
                    $Web.IsRootWeb,
                    $Web.AllowAnonymousAccess,
                    $Web.Created,
                    $Web.MasterUrl,
                    $Web.CustomMasterUrl,
                    $web.CustomJavaScriptFileUrl,
                    $web.AlternateCssUrl,
                    $Web.ThemedCssFolderUrl,
                    $Web.Theme,
                    $Web.QuickLaunchEnabled,
                    $Web.TreeViewEnabled,
                    $Web.EventHandlersEnabled,
                    $Web.Provisioned,
                    $Web.NoCrawl,
                    $Web.Features.Count,
                    $Web.UserCustomActions.Count,
                    $Web.EventReceivers.Count,
                    $Web.WorkflowAssociations.Count
            }
        
            If($WebXMLElement -ne $null)
            {
                Add-XMLAttribute $WebXMLElement "Id" $Web.Id.Guid
                Add-XMLAttribute $WebXMLElement "ParentWebId" $Web.ParentWebId.Guid
                Add-XMLAttribute $WebXMLElement "Url" $Web.Url
                Add-XMLAttribute $WebXMLElement "WebTemplateId" $Web.WebTemplateId
                Add-XMLAttribute $WebXMLElement "WebTemplate" $Web.WebTemplate
                Add-XMLAttribute $WebXMLElement "Configuration" $Web.Configuration
                Add-XMLAttribute $WebXMLElement "Language" $Web.Language
                Add-XMLAttribute $WebXMLElement "Title" $Web.Title
                Add-XMLAttribute $WebXMLElement "UIVersion" $Web.UIVersion
                Add-XMLAttribute $WebXMLElement "UIVersionConfigurationEnabled" $Web.UIVersionConfigurationEnabled
                Add-XMLAttribute $WebXMLElement "LastItemModifiedDate" $Web.LastItemModifiedDate
                Add-XMLAttribute $WebXMLElement "IsRootWeb" $Web.IsRootWeb
                Add-XMLAttribute $WebXMLElement "IsMultilingual" $Web.IsMultilingual
                Add-XMLAttribute $WebXMLElement "AllowAnonymousAccess" $Web.AllowAnonymousAccess
                Add-XMLAttribute $WebXMLElement "MasterPageReferenceEnabled" $Web.MasterPageReferenceEnabled
                Add-XMLAttribute $WebXMLElement "Created" $Web.Created
                Add-XMLAttribute $WebXMLElement "PortalMember" $Web.PortalMember
                Add-XMLAttribute $WebXMLElement "PortalSubscriptionUrl" $Web.PortalSubscriptionUrl
                Add-XMLAttribute $WebXMLElement "PortalUrl" $Web.PortalUrl
                Add-XMLAttribute $WebXMLElement "MasterUrl" $Web.MasterUrl
                Add-XMLAttribute $WebXMLElement "CustomMasterUrl" $Web.CustomMasterUrl
                Add-XMLAttribute $WebXMLElement "CustomJavaScriptFileUrl" $web.CustomJavaScriptFileUrl
                Add-XMLAttribute $WebXMLElement "AlternateCssUrl" $web.AlternateCssUrl
                Add-XMLAttribute $WebXMLElement "ThemedCssFolderUrl" $Web.ThemedCssFolderUrl
                Add-XMLAttribute $WebXMLElement "ThemedCssUrl" $Web.ThemedCssUrl
                Add-XMLAttribute $WebXMLElement "Theme" $Web.Theme
                Add-XMLAttribute $WebXMLElement "QuickLaunchEnabled" $Web.QuickLaunchEnabled
                Add-XMLAttribute $WebXMLElement "TreeViewEnabled" $Web.TreeViewEnabled
                Add-XMLAttribute $WebXMLElement "EventHandlersEnabled" $Web.EventHandlersEnabled
                Add-XMLAttribute $WebXMLElement "Provisioned" $Web.Provisioned
                Add-XMLAttribute $WebXMLElement "NoCrawl" $Web.NoCrawl
                Add-XMLAttribute $WebXMLElement "ExcludeFromOfflineClient" $Web.ExcludeFromOfflineClient
                Add-XMLAttribute $WebXMLElement "SyndicationEnabled" $Web.SyndicationEnabled
                Add-XMLAttribute $WebXMLElement "AllowRssFeeds" $Web.AllowRssFeeds
                Add-XMLAttribute $WebXMLElement "FeaturesCount" $Web.Features.Count
                Add-XMLAttribute $WebXMLElement "UserCustomActionsCount" $Web.UserCustomActions.Count
                Add-XMLAttribute $WebXMLElement "EventReceiversCount" $Web.EventReceivers.Count
                Add-XMLAttribute $WebXMLElement "WorkflowAssocationsCount" $Web.WorkflowAssociations.Count
            }

            #List Web Users
            If($WebXMLElement -ne $null)
            {
                $UsersXMLElement = Add-XMLElement $WebXMLElement "Users"
            }
            ForEach($WebUser In $Web.Users)
            {
                If($WebUser -ne $null)
                {
                    Get-SPUserMigrationData $WebUser $UsersXMLElement -HideOutput:$HideOutput
                }
            }

            #List Web Groups
            If($WebXMLElement -ne $null)
            {
                $GroupsXMLElement = Add-XMLElement $WebXMLElement "Groups"
            }
            ForEach($WebGroup In $Web.Groups)
            {
                If($WebGroup -ne $null)
                {
                    Get-SPGroupMigrationData $WebGroup $GroupsXMLElement -HideOutput:$HideOutput
                }
            }
                
            #List Web Features
            If($Web.Features.Count -gt 0)
            {
                Get-SPFeatureCollectionMigrationData $Web.Features $WebXMLElement -HideOutput:$HideOutput
            }

            #List Web UserCustomActions
            If($Web.UserCustomActions.Count -gt 0)
            {
               Get-SPUserCustomActionCollectionMigrationData $Web.UserCustomActions $WebXMLElement -HideOutput:$HideOutput
            }

            #List Web EventReceivers
            If($Web.EventReceivers.Count -gt 0)
            {
                Get-SPEventReceiverDefinitionCollectionMigrationData $Web.EventReceivers $WebXMLElement -HideOutput:$HideOutput
            }
        
            #List Web's WebPartPage Files
            try
            {
                $IsPublishingWeb = [Microsoft.SharePoint.Publishing.PublishingWeb]::IsPublishingWeb($Web)
            }
            Catch [Exception]
            {
                Write-Host "Error: Web ", ($File.Web.Url + "/" + $File.Url), "has issue with IsPublishingWeb" -ForegroundColor ([System.ConsoleColor]::DarkYellow)
                Write-Host "$($_.Exception.GetType().FullName) : $($_.Exception.Message)" -ForegroundColor ([System.ConsoleColor]::DarkYellow)
            }

            If($WebXMLElement -ne $null)
            {
                $FilesXMLElement = Add-XMLElement $WebXMLElement "Files"
            }
            Get-SPFileCollectionMigrationData $Web.Files $FilesXMLElement -HideOutput:$HideOutput

            $MasterPageGallery = $web.GetCatalog([Microsoft.SharePoint.SPListTemplateType]::MasterPageCatalog)
            if($MasterPageGallery)
            {
                Get-SPListItemCollectionMigrationData $MasterPageGallery.Items $FilesXMLElement -HideOutput:$HideOutput
            }

            $PagesLibrary = $null
            If($IsPublishingWeb)
            { 
                $PublishingWeb = [Microsoft.SharePoint.Publishing.PublishingWeb]::GetPublishingWeb($Web)
                $PagesLibrary = $PublishingWeb.PagesList
            }
            else
            {
                $PagesLibrary = $Web.Lists["Site Pages"]
            }

            if($PagesLibrary -ne $null)
            {
                Get-SPListItemCollectionMigrationData $PagesLibrary.Items $FilesXMLElement -HideOutput:$HideOutput
            }
        
            #List Web SupportedUICultures
            If($WebXMLElement -ne $null)
            {
                $SupportedUICulturesXMLElement = Add-XMLElement $WebXMLElement "SupportedUICultures"
            }
            ForEach($Culture In $Web.SupportedUICultures)
            {
                Get-SPCultureInfoMigrationData $Culture $SupportedUICulturesXMLElement -HideOutput:$HideOutput
            }
            
            If($Web.WorkflowAssociations.Count -gt 0)
            {
                Get-SPWorkflowAssociationCollectionMigrationData $Web.WorkflowAssociations $WebXMLElement -HideOutput:$HideOutput
            }

            #Gather Web Navigation Structure
            Get-SPNavigationMigrationData $Web.Navigation $WebXMLElement -HideOutput:$HideOutput
        
            #Gather Web Lists
            Get-SPListCollectionMigrationData $Web.Lists $WebXMLElement -HideOutput:$HideOutput
        }
    }
}

#Get migration related data from a passed in SPGroup
function Get-SPGroupMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPGroupCollection')]
        [Microsoft.SharePoint.SPGroup]$Group,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $GroupXMLElement = Add-XMLElement $ParentXMLNode "Group"
        }
        
        If (!$HideOutput.ToBool())
        {
            Write-Host $Group.Id,
                $Group.LoginName,
                $Group.Name,
                $Group.Owner.Id,
                $Group.DistributionGroupAlias,
                $Group.DistributionGroupEmail,
                $Group.AllowMembersEditMembership,
                $Group.AllowRequestToJoinLeave,
                $Group.AutoAcceptRequestToJoinLeave,
                $Group.OnlyAllowMembersViewMembership,
                $Group.Description,
                $Group.Roles.Count
        }
        
        If($GroupXMLElement -ne $null)
        {
            Add-XMLAttribute $GroupXMLElement "Id" $Group.Id
            Add-XMLAttribute $GroupXMLElement "LoginName" $Group.LoginName
            Add-XMLAttribute $GroupXMLElement "Name" $Group.Name
            Add-XMLAttribute $GroupXMLElement "Owner" $Group.Owner.Id
            Add-XMLAttribute $GroupXMLElement "DistributionGroupAlias" $Group.DistributionGroupAlias
            Add-XMLAttribute $GroupXMLElement "DistributionGroupEmail" $Group.DistributionGroupEmail
            Add-XMLAttribute $GroupXMLElement "AllowMembersEditMembership" $Group.AllowMembersEditMembership
            Add-XMLAttribute $GroupXMLElement "AllowRequestToJoinLeave" $Group.AllowRequestToJoinLeave
            Add-XMLAttribute $GroupXMLElement "AutoAcceptRequestToJoinLeave" $Group.AutoAcceptRequestToJoinLeave
            Add-XMLAttribute $GroupXMLElement "OnlyAllowMembersViewMembership" $Group.OnlyAllowMembersViewMembership
            Add-XMLAttribute $GroupXMLElement "Description" $Group.Description
            Add-XMLAttribute $GroupXMLElement "RolesCount" $Group.Roles.Count
        }
    }
}

#Get migration related data from a passed in SPUser
function Get-SPUserMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPUser')]
        [Microsoft.SharePoint.SPUser]$User,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $UserXMLElement = Add-XMLElement $ParentXMLNode "User"
        }
        
        If (!$HideOutput.ToBool())
        {
            Write-Host $User.Id,
                $User.LoginName,
                $User.UserLogin,
                $User.Name,
                $User.DisplayName,
                $User.Email,
                $User.Sid,
                $User.IsApplicationPrincipal,
                $User.IsDomainGroup,
                $User.IsSiteAdmin,
                $User.IsSiteAuditor,
                $User.Alerts.Count
        }
        
        If($UserXMLElement -ne $null)
        {
            Add-XMLAttribute $UserXMLElement "Id" $User.Id
            Add-XMLAttribute $UserXMLElement "LoginName" $User.LoginName
            Add-XMLAttribute $UserXMLElement "UserLogin" $User.UserLogin
            Add-XMLAttribute $UserXMLElement "Name" $User.Name
            Add-XMLAttribute $UserXMLElement "DisplayName" $User.DisplayName
            Add-XMLAttribute $UserXMLElement "Email" $User.Email
            Add-XMLAttribute $UserXMLElement "Sid" $User.Sid
            Add-XMLAttribute $UserXMLElement "IsApplicationPrincipal" $User.IsApplicationPrincipal
            Add-XMLAttribute $UserXMLElement "IsDomainGroup" $User.IsDomainGroup
            Add-XMLAttribute $UserXMLElement "IsSiteAdmin" $User.IsSiteAdmin
            Add-XMLAttribute $UserXMLElement "IsSiteAuditor" $User.IsSiteAuditor
            Add-XMLAttribute $UserXMLElement "AlertsCount" $User.Alerts.Count
        }
    }
}

#Get migration related data from a passed in SPListCollection
function Get-SPListCollectionMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPListCollection')]
        [Microsoft.SharePoint.SPListCollection]$Lists,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $ListsXMLElement = Add-XMLElement $ParentXMLNode "Lists"
        }
        
        ForEach($List In $Lists)
        {
            If($ListsXMLElement -ne $null)
            {
                $ListXMLElement = Add-XMLElement $ListsXMLElement "List"
            }

            If (!$HideOutput.ToBool())
            {
                Write-Host $List.Id.Guid,
                    $List.Title,
                    $List.RootFolder.Url,
                    $List.IsCatalog,
                    $List.Hidden,
                    $List.Items.Count,
                    $List.BaseType,
                    $List.BaseTemplate,
                    $List.TemplateFeatureId.Guid,
                    $List.ContentTypes.Count,
                    $List.EventReceivers.Count,
                    $List.WorkflowAssociations.Count
            }
            
            If($ListXMLElement -ne $null)
            {
                Add-XMLAttribute $ListXMLElement "Id" $List.Id.Guid
                Add-XMLAttribute $ListXMLElement "Title" $List.Title
                Add-XMLAttribute $ListXMLElement "RootFolderUrl" ($List.ParentWeb.Url + "/" + $List.RootFolder.Url)
                Add-XMLAttribute $ListXMLElement "IsCatalog" $List.IsCatalog    #Note: This property will not show up in all lists
                Add-XMLAttribute $ListXMLElement "Hidden" $List.Hidden
                Add-XMLAttribute $ListXMLElement "Items" $List.Items.Count
                Add-XMLAttribute $ListXMLElement "BaseType" $List.BaseType
                Add-XMLAttribute $ListXMLElement "BaseTemplate" $List.BaseTemplate
                Add-XMLAttribute $ListXMLElement "TemplateFeatureId" $List.TemplateFeatureId.Guid
                Add-XMLAttribute $ListXMLElement "ContentTypesCount" $List.ContentTypes.Count
                Add-XMLAttribute $ListXMLElement "EventReceiversCount" $List.EventReceivers.Count
                Add-XMLAttribute $ListXMLElement "WorkflowAssociationsCount" $List.WorkflowAssociations.Count
            }
            
            If($List.ContentTypes.Count -gt 0)
            {
                Get-SPContentTypeCollectionMigrationData $List.ContentTypes $ListXMLElement -HideOutput:$HideOutput
            }

            If($List.EventReceivers.Count -gt 0)
            {
                Get-SPEventReceiverDefinitionCollectionMigrationData $List.EventReceivers $ListXMLElement -HideOutput:$HideOutput
            }

            If($List.WorkflowAssociations.Count -gt 0)
            {
                Get-SPWorkflowAssociationCollectionMigrationData $List.WorkflowAssociations $ListXMLElement -HideOutput:$HideOutput
            }
            
            <# #Gather all aspx pages data
            If($ListXMLElement -ne $null)
            {
                $FilesXMLElement = Add-XMLElement $ListXMLElement "Files"
            }
            Get-SPListItemCollectionMigrationData $PagesLibrary.Items $FilesXMLElement -HideOutput:$HideOutput
            #>
        }
    }
}

#Get migration related data from a passed in SPNavigation
function Get-SPNavigationMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPNavigation')]
        [Microsoft.SharePoint.Navigation.SPNavigation]$Navigation,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            If(($Navigation.GlobalNodes.Count -gt 0) -or ($Navigation.TopNavigationBar.Count -gt 0) -or ($Navigation.QuickLaunch.Count -gt 0))
            {
                $NavigationXMLElement = Add-XMLElement $ParentXMLNode "Navigation"
                
                Add-XMLAttribute $NavigationXMLElement "GlobalNodesCount" $Navigation.GlobalNodes.Count
                Add-XMLAttribute $NavigationXMLElement "TopNavigationBarCount" $Navigation.TopNavigationBar.Count
                Add-XMLAttribute $NavigationXMLElement "QuickLaunchCount" $Navigation.QuickLaunch.Count
                Add-XMLAttribute $NavigationXMLElement "UseShared" $Navigation.UseShared
            }
        }

        If($Navigation.Home -ne $null)
        {
            If($NavigationXMLElement -ne $null)
            {
                $HomeNodeXMLElement = Add-XMLElement $NavigationXMLElement "Home"
            }
            
            Get-SPNavigationNodeMigrationData $Navigation.Home $HomeNodeXMLElement -HideOutput:$HideOutput
        }

        If($Navigation.GlobalNodes.Count -gt 0)
        {
            If($NavigationXMLElement -ne $null)
            {
                $GlobalNodesXMLElement = Add-XMLElement $NavigationXMLElement "GlobalNodes"
            }
            
            ForEach($GlobalNavigationNode In $Navigation.GlobalNodes)
            {
                Get-SPNavigationNodeMigrationData $GlobalNavigationNode $GlobalNodesXMLElement -HideOutput:$HideOutput
            }
        }
    
    
        If($Navigation.TopNavigationBar.Count -gt 0)
        {
            If($NavigationXMLElement -ne $null)
            {
                $TopNavBarNodesXMLElement = Add-XMLElement $NavigationXMLElement "TopNavigationBar"
            }
            
            ForEach($TopNavBarNode In $Navigation.TopNavigationBar)
            {
                Get-SPNavigationNodeMigrationData $TopNavBarNode $TopNavBarNodesXMLElement -HideOutput:$HideOutput
            }
        }

        If($Navigation.QuickLaunch.Count -gt 0)
        {
            If($NavigationXMLElement -ne $null)
            {
                $QuickLaunchNodesXMLElement = Add-XMLElement $NavigationXMLElement "QuickLaunch"
            }
            
            ForEach($QuickLaunchNode In $Navigation.QuickLaunch)
            {
                Get-SPNavigationNodeMigrationData $QuickLaunchNode $QuickLaunchNodesXMLElement -HideOutput:$HideOutput
            }
        }
    }
}

#Get migration related data from a passed in SPNavigationNode
function Get-SPNavigationNodeMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPNavigationNode')]
        [Microsoft.SharePoint.Navigation.SPNavigationNode]$NavigationNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $NavigationNodeXMLElement = Add-XMLElement $ParentXMLNode "NavigationNode"
        }
        
        If(!$HideOutput.ToBool())
        {
            Write-Host $NavigationNode.Id,
                $NavigationNode.ParentId,
                $NavigationNode.Title,
                $NavigationNode.Url,
                $NavigationNode.IsVisible,
                $NavigationNode.IsExternal,
                $NavigationNode.Children.Count
        }

        If($NavigationNodeXMLElement -ne $null)
        {
            Add-XMLAttribute $NavigationNodeXMLElement "Id" $NavigationNode.Id
            Add-XMLAttribute $NavigationNodeXMLElement "ParentId" $NavigationNode.ParentId
            Add-XMLAttribute $NavigationNodeXMLElement "Title" $NavigationNode.Title
            Add-XMLAttribute $NavigationNodeXMLElement "RootFolderUrl" $NavigationNode.Url
            Add-XMLAttribute $NavigationNodeXMLElement "IsVisible" $NavigationNode.IsVisible
            Add-XMLAttribute $NavigationNodeXMLElement "IsExternal" $NavigationNode.IsExternal
            Add-XMLAttribute $NavigationNodeXMLElement "ChildrenCount" $NavigationNode.Children.Count
        }
        
        ForEach($ChildNavigationNode In $NavigationNode.Children)
        {
            Get-SPNavigationNodeMigrationData $ChildNavigationNode $ParentXMLNode -HideOutput:$HideOutput
        }
    }
}

#Get migration related data from a passed in SPCultureInfo object
function Get-SPCultureInfoMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Globalization.CultureInfo]$CultureInfo,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $CultureInfoXMLElement = Add-XMLElement $ParentXMLNode "Culture"
        }

        If(!$HideOutput.ToBool())
        {
            Write-Host $CultureInfo.LCID,
                $CultureInfo.Name
        }

        If($CultureInfoXMLElement -ne $null)
        {
            Add-XMLAttribute $CultureInfoXMLElement "LCID" $CultureInfo.LCID
            Add-XMLAttribute $CultureInfoXMLElement "Name" $CultureInfo.Name
        }
    }
}


#Get migration related data from a passed in SPUserSolutionCollection
function Get-SPUserSolutionCollectionMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPUserSolutionCollection')]
        [Microsoft.SharePoint.SPUserSolutionCollection]$Solutions,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $SolutionsXMLElement = Add-XMLElement $ParentXMLNode "UserSolutions"
        }
        
        ForEach($Solution In $Solutions)
        {
            If($SolutionsXMLElement -ne $null)
            {
                $SolutionXMLElement = Add-XMLElement $SolutionsXMLElement "UserSolution"
            }

            If(!$HideOutput.ToBool())
            {
                Write-Host $Solution.SolutionId.Guid,
                    $Solution.Name,
                    $Solution.Signature,
                    $Solution.HasAssemblies,
                    $Solution.Status
            }
        
            If($SolutionXMLElement -ne $null)
            {
                Add-XMLAttribute $SolutionXMLElement "Id" $Solution.SolutionId.Guid
                Add-XMLAttribute $SolutionXMLElement "Name" $Solution.Name
                Add-XMLAttribute $SolutionXMLElement "Signature" $Solution.Signature
                Add-XMLAttribute $SolutionXMLElement "HasAssemblies" $Solution.HasAssemblies
                Add-XMLAttribute $SolutionXMLElement "Status" $Solution.Status
            }
        }
    }
}

#Get migration related data from a passed in SPFeatureCollection
function Get-SPFeatureCollectionMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPFeatureCollection')]
        [Microsoft.SharePoint.SPFeatureCollection]$Features,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $FeaturesXMLElement = Add-XMLElement $ParentXMLNode "Features"
        }

        ForEach($Feature in $Features)
        {
            If($FeaturesXMLElement -ne $null)
            {
                $FeatureXMLElement = Add-XMLElement $FeaturesXMLElement "Feature"
            }

            If(!$HideOutput.ToBool())
            {
                Write-Host $Feature.DefinitionId.Guid,
                    $Feature.FeatureDefinitionScope,
                    ([String]$Feature.Version),
                    $Feature.Definition.DisplayName,
                    $Feature.Definition.Scope,
                    ([String]$Feature.Definition.Version),
                    $Feature.Definition.Hidden
            }

            If($FeatureXMLElement -ne $null)
            {
                Add-XMLAttribute $FeatureXMLElement "Id" $Feature.DefinitionId.Guid
                Add-XMLAttribute $FeatureXMLElement "Scope" $Feature.FeatureDefinitionScope
                Add-XMLAttribute $FeatureXMLElement "Version" ([String]$Feature.Version)
                Add-XMLAttribute $FeatureXMLElement "Definition_Id" $Feature.DefinitionId.Guid
                Add-XMLAttribute $FeatureXMLElement "Definition_DisplayName" $Feature.Definition.DisplayName
                Add-XMLAttribute $FeatureXMLElement "Definition_Scope" $Feature.Definition.Scope
                Add-XMLAttribute $FeatureXMLElement "Definition_Version" ([String]$Feature.Definition.Version)
                Add-XMLAttribute $FeatureXMLElement "Definition_Hidden" $Feature.Definition.Hidden
            }
        }
    }
}

#Get migration related data from a passed in SPUserCustomActionCollection
function Get-SPUserCustomActionCollectionMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPUserCustomActionCollection')]
        [Microsoft.SharePoint.SPUserCustomActionCollection]$UserCustomActions,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $UserCustomActionsXMLElement = Add-XMLElement $ParentXMLNode "UserCustomActions"
        }

        ForEach($UserCustomAction In $UserCustomActions)
        {
            If($UserCustomActionsXMLElement -ne $null)
            {
                $UserCustomActionXMLElement = Add-XMLElement $UserCustomActionsXMLElement "UserCustomAction"
            }

            If(!$HideOutput.ToBool())
            {
                Write-Host $UserCustomAction.Id.Guid,
                    $UserCustomAction.Name,
                    $UserCustomAction.RegistrationId.Guid,
                    $UserCustomAction.RegistrationType,
                    $UserCustomAction.Location,
                    $UserCustomAction.Group
            }

            If($UserCustomActionXMLElement -ne $null)
            {
                Add-XMLAttribute $UserCustomActionXMLElement "Id" $UserCustomAction.Id.Guid
                Add-XMLAttribute $UserCustomActionXMLElement "Name" $UserCustomAction.Name
                Add-XMLAttribute $UserCustomActionXMLElement "RegistrationId" $UserCustomAction.RegistrationId.Guid
                Add-XMLAttribute $UserCustomActionXMLElement "RegistrationType" $UserCustomAction.RegistrationType
                Add-XMLAttribute $UserCustomActionXMLElement "Location" $UserCustomAction.Location
                Add-XMLAttribute $UserCustomActionXMLElement "Group" $UserCustomAction.Group
            }
        }
    }
}

#Get migration related data from a passed in SPContentTypeCollection
function Get-SPContentTypeCollectionMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPContentTypeCollection')]
        [Microsoft.SharePoint.SPContentTypeCollection]$ContentTypes,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $ContentTypesXMLElement = Add-XMLElement $ParentXMLNode "ContentTypes"
        }

        ForEach($ContentType In $ContentTypes)
        {
            If($ContentTypesXMLElement -ne $null)
            {
                $ContentTypeXMLElement = Add-XMLElement $ContentTypesXMLElement "ContentType"
            }

            If(!$HideOutput.ToBool())
            {
                Write-Host $ContentType.Id,
                    $ContentType.Name,
                    $ContentType.FeatureId.Guid,
                    $ContentType.Group,
                    $ContentType.Hidden,
                    $ContentType.ReadOnly,
                    $ContentType.Sealed,
                    $ContentType.Scope,
                    ([String]$ContentType.Version)
            }

            If($ContentTypeXMLElement -ne $null)
            {
                Add-XMLAttribute $ContentTypeXMLElement "Id" $ContentType.Id
                Add-XMLAttribute $ContentTypeXMLElement "Name" $ContentType.Name
                Add-XMLAttribute $ContentTypeXMLElement "FeatureId" $ContentType.FeatureId.Guid
                Add-XMLAttribute $ContentTypeXMLElement "Group" $ContentType.Group
                Add-XMLAttribute $ContentTypeXMLElement "Hidden" $ContentType.Hidden
                Add-XMLAttribute $ContentTypeXMLElement "ReadOnly" $ContentType.ReadOnly
                Add-XMLAttribute $ContentTypeXMLElement "Sealed" $ContentType.Sealed
                Add-XMLAttribute $ContentTypeXMLElement "Scope" $ContentType.Scope
                Add-XMLAttribute $ContentTypeXMLElement "Version" ([String]$ContentType.Version)
            }
        }
    }
}

#Get migration related data from a passed in SPWorkflowAssociationCollection
function Get-SPWorkflowAssociationCollectionMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPWorkflowAssociationsCollection')]
        [Microsoft.SharePoint.Workflow.SPWorkflowAssociationCollection]$WorkflowAssociations,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $WorkflowAssociationsXMLElement = Add-XMLElement $ParentXMLNode "WorkflowAssociations"
        }

        ForEach($WorkflowAssociation In $WorkflowAssociations)
        {
            If($WorkflowAssociationsXMLElement -ne $null)
            {
                $WorkflowAssociationXMLElement = Add-XMLElement $WorkflowAssociationsXMLElement "WorkflowAssociation"
            }

            If(!$HideOutput.ToBool())
            {
                Write-Host $WorkflowAssociation.Id.Guid,
                    $WorkflowAssociation.Name,
                    $WorkflowAssociation.BaseId.Guid,
                    $WorkflowAssociation.BaseTemplate,
                    $WorkflowAssociation.HistoryListId.Guid,
                    $WorkflowAssociation.TaskListId.Guid,
                    $WorkflowAssociation.Author.Id,
                    $WorkflowAssociation.Author.UserLogin,
                    $WorkflowAssociation.Enabled,
                    $WorkflowAssociation.IsDeclarative
            }

            If($WorkflowAssociationXMLElement -ne $null)
            {
                Add-XMLAttribute $WorkflowAssociationXMLElement "Id" $WorkflowAssociation.Id.Guid
                Add-XMLAttribute $WorkflowAssociationXMLElement "Name" $WorkflowAssociation.Name
                Add-XMLAttribute $WorkflowAssociationXMLElement "BaseId" $WorkflowAssociation.BaseId.Guid
                Add-XMLAttribute $WorkflowAssociationXMLElement "BaseTemplate" $WorkflowAssociation.BaseTemplate
                Add-XMLAttribute $WorkflowAssociationXMLElement "HistoryListId" $WorkflowAssociation.HistoryListId.Guid
                Add-XMLAttribute $WorkflowAssociationXMLElement "TaskListId" $WorkflowAssociation.TaskListId.Guid
                Add-XMLAttribute $WorkflowAssociationXMLElement "Author_Id" $WorkflowAssociation.Author.Id
                Add-XMLAttribute $WorkflowAssociationXMLElement "Author_UserLogin" $WorkflowAssociation.Author.UserLogin
                Add-XMLAttribute $WorkflowAssociationXMLElement "Enabled" $WorkflowAssociation.Enabled
                Add-XMLAttribute $WorkflowAssociationXMLElement "IsDeclarative" $WorkflowAssociation.IsDeclarative
            }
        }
    }
}

#Get migration related data from a passed in SPEventReceiverDefinitionCollection
function Get-SPEventReceiverDefinitionCollectionMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPEventReceiverDefinitionCollection')]
        [Microsoft.SharePoint.SPEventReceiverDefinitionCollection]$EventReceivers,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        If($ParentXMLNode -ne $null)
        {
            $EventReceiversXMLElement = Add-XMLElement $ParentXMLNode "EventReceivers"
        }

        ForEach($EventReceiver in $EventReceivers)
        {
            If($EventReceiversXMLElement -ne $null)
            {
                $EventReceiverXMLElement = Add-XMLElement $EventReceiversXMLElement "EventReceiver"
            }

            If(!$HideOutput.ToBool())
            {
                Write-Host $EventReceiver.Id.Guid,
                    $EventReceiver.SiteId.Guid,
                    $EventReceiver.WebId.Guid,
                    $EventReceiver.HostId.Guid,
                    $EventReceiver.SequenceNumber,
                    $EventReceiver.Name,
                    $EventReceiver.Assembly,
                    $EventReceiver.Class,
                    $EventReceiver.Type
            }

            If($EventReceiverXMLElement -ne $null)
            {
                Add-XMLAttribute $EventReceiverXMLElement "Id" $EventReceiver.Id.Guid
                Add-XMLAttribute $EventReceiverXMLElement "SiteId" $EventReceiver.SiteId.Guid
                Add-XMLAttribute $EventReceiverXMLElement "WebId" $EventReceiver.WebId.Guid
                Add-XMLAttribute $EventReceiverXMLElement "HostId" $EventReceiver.HostId.Guid
                Add-XMLAttribute $EventReceiverXMLElement "SequenceNumber" $EventReceiver.SequenceNumber
                Add-XMLAttribute $EventReceiverXMLElement "Name" $EventReceiver.Name
                Add-XMLAttribute $EventReceiverXMLElement "Assembly" $EventReceiver.Assembly
                Add-XMLAttribute $EventReceiverXMLElement "Class" $EventReceiver.Class
                Add-XMLAttribute $EventReceiverXMLElement "Type" $EventReceiver.Type
            }
        }
    }
}

#Get migration related web page data from a passed in SPListItemCollection
function Get-SPListItemCollectionMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPListItemCollection')]
        [Microsoft.SharePoint.SPListItemCollection]$Items,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        ForEach($ListItem in $Items)
        {
            If($ListItem.File.Name -like "*.aspx" -or $ListItem.File.Name -like "*.master")
            {
                If(!$HideOutput.ToBool())
                {
                    Write-Host $ListItem.File.Name,
                        $ListItem.File.Author.Id,
                        $ListItem.File.Author.UserLogin,
                        $ListItem.File.LockedByUser.Id,
                        $ListItem.File.LockedByUser.UserLogin,
                        $ListItem.File.CheckedOutDate,
                        $ListItem.File.LockType,
                        ($ListItem.Web.Url + "/" + $ListItem.File.Url),
                        $ListItem.File.Level,
                        $ListItem.File.CustomizedPageStatus
                }

                If($ParentXMLNode -ne $null)
                {
                    $FileXMLElement = Add-XMLElement $ParentXMLNode "WebPage"

                    Add-XMLAttribute $FileXMLElement "Name" $ListItem.File.Name
                    Add-XMLAttribute $FileXMLElement "Author_Id" $ListItem.File.Author.Id
                    Add-XMLAttribute $FileXMLElement "Author_UserLogin" $ListItem.File.Author.UserLogin
                    Add-XMLAttribute $FileXMLElement "LockedByUser_Id" $ListItem.File.LockedByUser.Id
                    Add-XMLAttribute $FileXMLElement "LockedByUser_UserLogin" $ListItem.File.LockedByUser.UserLogin
                    Add-XMLAttribute $FileXMLElement "CheckedOutDate" $ListItem.File.CheckedOutDate
                    Add-XMLAttribute $FileXMLElement "LockType" $ListItem.File.LockType
                    Add-XMLAttribute $FileXMLElement "Url" ($ListItem.Web.Url + "/" + $ListItem.File.Url)
                    Add-XMLAttribute $FileXMLElement "Level" $ListItem.File.Level
                    Add-XMLAttribute $FileXMLElement "CustomizedPageStatus" $ListItem.File.CustomizedPageStatus
                }
                
                If($ListItem.File.Name -like "*.aspx")
                {
                    #Get web part information on web part page
                    Get-SPWebPartsMigrationData $ListItem.File $FileXMLElement -HideOutput:$HideOutput
                }
            }
        }
    }
}

#Get migration related web page data from a passed in SPListItemCollection
function Get-SPFileCollectionMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPFileCollection')]
        [Microsoft.SharePoint.SPFileCollection]$Files,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        ForEach($File in $Files)
        {
            If($File.Name -like "*.aspx" -or $File.Name -like "*.master")
            {
                If(!$HideOutput.ToBool())
                {
                    Write-Host $File.Name,
                        $File.Author.Id,
                        $File.Author.UserLogin,
                        $File.LockedByUser.Id,
                        $File.LockedByUser.UserLogin,
                        $File.CheckedOutDate,
                        $File.LockType,
                        ($File.Web.Url + "/" + $File.Url),
                        $File.Level,
                        $File.CustomizedPageStatus
                }

                If($ParentXMLNode -ne $null)
                {
                    $FileXMLElement = Add-XMLElement $ParentXMLNode "WebPage"
                    
                    Add-XMLAttribute $FileXMLElement "Name" $File.Name
                    Add-XMLAttribute $FileXMLElement "Author_Id" $File.Author.Id
                    Add-XMLAttribute $FileXMLElement "Author_UserLogin" $File.Author.UserLogin
                    Add-XMLAttribute $FileXMLElement "LockedByUser_Id" $File.LockedByUser.Id
                    Add-XMLAttribute $FileXMLElement "LockedByUser_UserLogin" $File.LockedByUser.UserLogin
                    Add-XMLAttribute $FileXMLElement "CheckedOutDate" $File.CheckedOutDate
                    Add-XMLAttribute $FileXMLElement "LockType" $File.LockType
                    Add-XMLAttribute $FileXMLElement "Url" ($File.Web.Url + "/" + $File.Url)
                    Add-XMLAttribute $FileXMLElement "Level" $File.Level
                    Add-XMLAttribute $FileXMLElement "CustomizedPageStatus" $File.CustomizedPageStatus
                }
                
                If($File.Name -like "*.aspx")
                {
                    #Get web part information on web part page
                    Get-SPWebPartsMigrationData $File $FileXMLElement -HideOutput:$HideOutput
                }
            }
        }
    }
}

function Get-SPWebPartsMigrationData
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('SPFile')]
        [Microsoft.SharePoint.SPFile]$File,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [System.Xml.XmlElement]$ParentXMLNode,
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [Switch]$HideOutput
    )
    process
    {
        #get web part manager and list web parts
        Try
        {
            $WebPartManager = $File.GetLimitedWebPartManager([System.Web.UI.WebControls.WebParts.PersonalizationScope]::Shared)       
        }
        Catch [Exception]
        {
            Write-Host "Error: Page ", ($File.Web.Url + "/" + $File.Url), "has a LimitedWebPartManager issue" -ForegroundColor ([System.ConsoleColor]::DarkYellow)
            Write-Host "$($_.Exception.GetType().FullName) : $($_.Exception.Message)" -ForegroundColor ([System.ConsoleColor]::DarkYellow)
        }

        If(($ParentXMLNode -ne $null) -and ($WebPartManager.WebParts.Count -gt 0 ))
        {
            $PageWebPartsXMLElement = Add-XMLElement $ParentXMLNode "WebParts"
        }

        if ($WebPartManager -ne $null)
        {
            ForEach($WebPart in $WebPartManager.WebParts)
            {
                If(!$HideOutput.ToBool())
                {
                    Write-Host $WebPart.Id,
                        $WebPart.Title,
                        $WebPart.WebBrowsableObject,
                        $WebPart.ZoneId,
                        $WebPart.PartOrder,
                        $WebPart.IsClosed,
                        $WebPart.Hidden,
                        $WebPart.IsGhosted
                }
            
                If($PageWebPartsXMLElement -ne $null)
                {
                    $WebPartXMLElement = Add-XMLElement $PageWebPartsXMLElement "WebPart"
                
                    #Add-XMLAttribute $WebPartXMLElement "Id" $WebPart.Id
                    Add-XMLAttribute $WebPartXMLElement "Title" $WebPart.Title
                    Add-XMLAttribute $WebPartXMLElement "WebBrowsableObject" $WebPart.WebBrowsableObject
                    Add-XMLAttribute $WebPartXMLElement "ZoneId" $WebPart.ZoneId
                    Add-XMLAttribute $WebPartXMLElement "Zone" $WebPart.Zone
                    Add-XMLAttribute $WebPartXMLElement "ZoneIndex" $WebPart.ZoneIndex
                    Add-XMLAttribute $WebPartXMLElement "ListId" $WebPart.ListId
                    Add-XMLAttribute $WebPartXMLElement "StorageKey" $WebPart.StorageKey
                    Add-XMLAttribute $WebPartXMLElement "PartOrder" $WebPart.PartOrder
                    Add-XMLAttribute $WebPartXMLElement "IsClosed" $WebPart.IsClosed
                    Add-XMLAttribute $WebPartXMLElement "Hidden" $WebPart.Hidden
                    Add-XMLAttribute $WebPartXMLElement "IsGhosted" $WebPart.IsGhosted
                }   
            }
        }
    }
}
