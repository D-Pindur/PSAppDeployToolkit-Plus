Function Import-VcConfigMgrApplication {
    <#
        .SYNOPSIS
            Creates Visual C++ Redistributable applications in a ConfigMgr site.

        .DESCRIPTION
            Creates an application in a Configuration Manager site for each Visual C++ Redistributable and includes setting whether the Redistributable can run on 32-bit or 64-bit Windows and the Uninstall key for detecting whether the Redistributable is installed.

            Use Get-VcList and Get-VcRedist to download the Redistributable and create the array of Redistributables for importing into ConfigMgr.
        
        .NOTES
            Author: Aaron Parker
            Twitter: @stealthpuppy

        .LINK
            https://docs.stealthpuppy.com/docs/vcredist/usage/importing-into-configmgr

        .PARAMETER VcList
            An array containing details of the Visual C++ Redistributables from Get-VcList.

        .PARAMETER Path
            A folder containing the downloaded Visual C++ Redistributables.

        .PARAMETER CMPath
            Specify a UNC path where the Visual C++ Redistributables will be distributed from

        .PARAMETER SMSSiteCode
            Specify the Site Code for ConfigMgr app creation.

        .PARAMETER AppFolder
            Import the Visual C++ Redistributables into a sub-folder. Defaults to "VcRedists".

        .PARAMETER Silent
            Add a completely silent command line install of the VcRedist with no UI. The default install is passive.

        .EXAMPLE
            $VcList = Get-VcList
            Save-VcRedist -VcList $VcList -Path "C:\Temp\VcRedist"
            Import-VcConfigMgrApplication -VcList $VcList -Path "C:\Temp\VcRedist" -CMPath "\\server\share\VcRedist" -SMSSiteCode LAB

            Description:
            Download the supported Visual C++ Redistributables to "C:\Temp\VcRedist", copy them to "\\server\share\VcRedist" and import as applications into the ConfigMgr site LAB.
    #>
    [Alias('Import-VcCmApp')]
    [CmdletBinding(SupportsShouldProcess = $True, HelpURI = "https://docs.stealthpuppy.com/docs/vcredist/usage/importing-into-configmgr")]
    [OutputType([System.Management.Automation.PSObject])]
    Param (
        [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline)]
        [ValidateNotNull()]
        [System.Management.Automation.PSObject] $VcList,

        [Parameter(Mandatory = $True, Position = 1)]
        [ValidateScript( { If (Test-Path $_ -PathType 'Container') { $True } Else { Throw "Cannot find path $_." } })]
        [System.String] $Path,

        [Parameter(Mandatory = $True, Position = 2)]
        [ValidateScript( { If (!([bool]([System.Uri]$CMPath).IsUnc)) { $True } Else { Throw "$_ must be a valid UNC path." } })]
        [System.String] $CMPath,

        [Parameter(Mandatory = $True, Position = 3)]
        [ValidateScript( { If ($_ -match "^[a-zA-Z0-9]{3}$") { $True } Else { Throw "$_ is not a valid ConfigMgr site code." } })]
        [System.String] $SMSSiteCode,

        [Parameter(Mandatory = $False, Position = 4)]
        [ValidatePattern('^[a-zA-Z0-9]+$')]
        [System.String] $AppFolder = "VcRedists",

        [Parameter(Mandatory = $False)]
        [System.Management.Automation.SwitchParameter] $Silent,

        [Parameter(Mandatory = $False, Position = 5)]
        [ValidatePattern('^[a-zA-Z0-9]+$')]
        [System.String] $MdtDrive = "DS001",

        [Parameter(Mandatory = $False, Position = 6)]
        [ValidatePattern('^[a-zA-Z0-9]+$')]
        [System.String] $Publisher = "Microsoft",

        [Parameter(Mandatory = $False, Position = 7)]
        [ValidatePattern('^[a-zA-Z0-9-]+$')]
        [System.String] $Language = "en-US",

        [Parameter(Mandatory = $False, Position = 8)]
        [ValidatePattern('^[a-zA-Z0-9\+ ]+$')]
        [System.String] $Keyword = "Visual C++ Redistributable"
    )

    Begin {
        # CMPath will be the network location for copying the Visual C++ Redistributables to
        $validPath = Get-ValidPath $Path
        try {
            Set-Location -Path $validPath -ErrorAction SilentlyContinue
        }
        catch [System.Exception] {
            Write-Warning -Message "$($MyInvocation.MyCommand): Failed to set location to [$validPath]."
            Throw $_.Exception.Message
            Exit
        }
        Write-Verbose -Message "$($MyInvocation.MyCommand): Set location to [$validPath]."
        
        If (Test-Path $CMPath) {
            # Copy VcRedists to the network location. Use robocopy for robustness
            If ($PSCmdlet.ShouldProcess("$($validPath) to $($CMPath)", "Copy")) {
                try {
                    $invokeProcessParams = @{
                        FilePath     = "$env:SystemRoot\System32\robocopy.exe"
                        ArgumentList = "*.exe $validPath $CMPath /S /XJ /R:1 /W:1 /NP /NJH /NJS /NFL /NDL"
                    }
                    Invoke-Process @invokeProcessParams
                }
                catch [System.Exception] {
                    Write-Warning -Message "$($MyInvocation.MyCommand): Failed to copy Redistributables from [$validPath] to [$CMPath]."
                    Throw $_.Exception.Message
                    Exit        
                }
            }

            # If the ConfigMgr console is installed, load the PowerShell module; Requires PowerShell module to be installed
            If (Test-Path $env:SMS_ADMIN_UI_PATH) {
                try {            
                    # Import the ConfigurationManager.psd1 module
                    Import-Module "$($env:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" | Out-Null
                }
                catch [System.Exception] {
                    Write-Warning -Message "$($MyInvocation.MyCommand): Could not load ConfigMgr Module. Please make sure that the ConfigMgr Console is installed."
                    Throw $_.Exception.Message
                    Exit
                }
            }
            Else {
                Write-Warning -Message "$($MyInvocation.MyCommand): Cannot find environment variable SMS_ADMIN_UI_PATH. Is the ConfigMgr Console and PowerShell module installed?"
                Throw $_.Exception.Message
                Exit
            }

            # Create the folder for importing the Redistributables into
            If ($AppFolder) {
                $DestFolder = "$($SMSSiteCode):\Application\$($AppFolder)"
                If ($PSCmdlet.ShouldProcess($DestFolder, "Creating")) {
                    try {
                        New-Item -Path $DestFolder -ErrorAction SilentlyContinue
                    }
                    catch [System.Exception] {
                        Write-Warning -Message "$($MyInvocation.MyCommand): Failed to create folder: [$DestFolder]."
                        Throw $_.Exception.Message
                        Break
                    }
                }
                If (Test-Path -Path $DestFolder) {
                    Write-Verbose -Message "$($MyInvocation.MyCommand): Importing into: [$DestFolder]."
                }
            }
            Else {
                Write-Verbose -Message "$($MyInvocation.MyCommand): Importing into: [$($SMSSiteCode):\Application]."
                $DestFolder = "$($SMSSiteCode):\Application"
            }
        }
        Else {
            Write-Warning -Message "$($MyInvocation.MyCommand): Unable to confirm $CMPath exists. Please check that $CMPath is valid."
            Exit
        }
    }
    
    Process {
        ForEach ($Vc in $VcList) {
            Write-Verbose -Message "Importing app: [$($Vc.Name)][$($Vc.Release)][$($Vc.Architecture)]"

            # Import as an application into ConfigMgr
            If ($PSCmdlet.ShouldProcess("$($Vc.Name) in $CMPath", "Import ConfigMgr app")) {
                
                # Create the ConfigMgr application with properties from the XML file
                If ((Get-Item -Path $DestFolder).PSDrive.Name -eq $SMSSiteCode) {
                    If ($pscmdlet.ShouldProcess($Vc.Name + " $($Vc.Architecture)", "Creating ConfigMgr application")) {

                        # Change to the SMS Application folder before importing the applications
                        Write-Verbose -Message "$($MyInvocation.MyCommand): Setting location to $($DestFolder)"
                        try {
                            Set-Location -Path $DestFolder -ErrorAction SilentlyContinue
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "$($MyInvocation.MyCommand): Failed to set location to [$DestFolder]."
                            Throw $_.Exception.Message
                            Continue
                        }
                                                
                        try {
                            # Splat New-CMApplication parameters, add the application and move into the target golder
                            $cmAppParams = @{
                                Name            = "$($Vc.Name) $($Vc.Architecture)"
                                Description     = "$($Publisher) $($Vc.Name) $($Vc.Architecture) imported by $($MyInvocation.MyCommand)"
                                SoftwareVersion = "$($Vc.Release) $($Vc.Architecture)"
                                LinkText        = $Vc.URL
                                Publisher       = $Publisher
                                Keyword         = $Keyword
                            }
                            $app = New-CMApplication @cmAppParams
                            If ($AppFolder) {
                                $app | Move-CMObject -FolderPath $DestFolder -ErrorAction SilentlyContinue | Out-Null
                            }
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "$($MyInvocation.MyCommand): Failed to create application $($Vc.Name) $($Vc.Architecture) with error: $CMAppError."
                            Throw $_.Exception.Message
                            Break
                        }
                        finally {
                            # Write app detail to the pipeline
                            Write-Output -InputObject $app
                        }

                        try {
                            Set-Location -Path $validPath -ErrorAction SilentlyContinue
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "$($MyInvocation.MyCommand): Failed to set location to [$validPath]."
                            Throw $_.Exception.Message
                            Continue
                        }
                        Write-Verbose -Message "$($MyInvocation.MyCommand): Set location to [$validPath]."
                    }

                    # Add a deployment type to the application
                    If ($pscmdlet.ShouldProcess($("$Vc.Name $($Vc.Architecture)"), "Adding deployment type")) {

                        # Change to the SMS Application folder before importing the applications
                        try {
                            Set-Location -Path $DestFolder -ErrorAction SilentlyContinue
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "$($MyInvocation.MyCommand): Failed to set location to [$DestFolder]."
                            Throw $_.Exception.Message
                            Break
                        }
                        Write-Verbose -Message "$($MyInvocation.MyCommand): Set location to [$DestFolder]."

                        try {
                            # Splat Add-CMScriptDeploymentType parameters and add the application deployment type
                            $cmScriptParams = @{
                                InstallCommand           = "$(Split-Path -Path $Vc.Download -Leaf) $(If($Silent) { $vc.SilentInstall } Else { $vc.Install })"
                                ContentLocation          = "$CMPath\$($Vc.Release)\$($Vc.Architecture)\$($Vc.ShortName)"
                                ProductCode              = $Vc.ProductCode
                                SourceUpdateProductCode  = $Vc.ProductCode
                                DeploymentTypeName       = ("SCRIPT_" + $Vc.Name)
                                UserInteractionMode      = "Hidden"
                                UninstallCommand         = "$env:SystemRoot\System32\msiexec.exe /x $($Vc.ProductCode) /qn-"
                                LogonRequirementType     = "WhetherOrNotUserLoggedOn"
                                InstallationBehaviorType = "InstallForSystem"
                                Comment                  = "Generated by $($MyInvocation.MyCommand)"
                                ErrorVariable            = "CMDtError"
                            }
                            $app | Add-CMScriptDeploymentType @cmScriptParams | Out-Null
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "$($MyInvocation.MyCommand): Failed to add script deployment type with error $CMDtError."
                            Throw $_.Exception.Message
                            Break
                        }

                        try {
                            Set-Location -Path $validPath -ErrorAction SilentlyContinue
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "$($MyInvocation.MyCommand): Failed to set location to [$validPath]."
                            Throw $_.Exception.Message
                            Break
                        }
                        Write-Verbose -Message "$($MyInvocation.MyCommand): Set location to [$validPath]."
                    }
                }
            }
        }
    }

    End {
        try {
            Set-Location -Path $validPath -ErrorAction SilentlyContinue
        }
        catch [System.Exception] {
            Write-Warning -Message "$($MyInvocation.MyCommand): Failed to set location to [$validPath]."
            Throw $_.Exception.Message
        }
        Write-Verbose -Message "$($MyInvocation.MyCommand): Set location to [$validPath]."
    }
}
