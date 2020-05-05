Function Update-VcMdtBundle {
    <#
        .SYNOPSIS
            Updates Visual C++ Redistributable application bundles in a Microsoft Deployment Toolkit share.

        .DESCRIPTION
            After importing or adding Visual C++ Redistributable applications in a Microsoft Deployment Toolkit share, an existing application bundle can be updated with GUIDs for the new Visual C++ Redistributable applications.

        .NOTES
            Author: Aaron Parker
            Twitter: @stealthpuppy

        .LINK
            https://docs.stealthpuppy.com/docs/vcredist/usage/update-vcmdtbundle

        .PARAMETER MdtPath
            The local or network path to the MDT deployment share.

        .PARAMETER AppFolder
            A sub-folder of Applications that the Visual C++ Redistributables are in. Defaults to "VcRedists".

        .PARAMETER Publisher
            Publisher name for the Visual C++ Redistributables bundle. Defaults to "Microsoft".

        .PARAMETER BundleName
            Application name for the bundle. Defaults to "Visual C++ Redistributables".

        .EXAMPLE
            Get-VcList | Save-VcRedist -Path C:\Temp\VcRedist
            Update-VcMdtApplication -VcList (Get-VcList) -Path C:\Temp\VcRedist -MdtPath \\server\deployment
            Update-VcMdtBundle -MdtPath \\server\deployment

            Description:
            Retrieves the list of Visual C++ Redistributables, downloads them to C:\Temp\VcRedist and updates each Redistributable in the MDT deployment share at \\server\deployment.
    #>
    [CmdletBinding(SupportsShouldProcess = $True, HelpURI = "https://docs.stealthpuppy.com/docs/vcredist/usage/update-vcmdtbundle")]
    [OutputType([System.Management.Automation.PSObject])]
    Param (
        [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline)]
        [ValidateScript( { If (Test-Path $_ -PathType 'Container') { $True } Else { Throw "Cannot find path $_" } })]
        [System.String] $MdtPath,

        [Parameter(Mandatory = $False)]
        [ValidatePattern('^[a-zA-Z0-9]+$')]
        [ValidateNotNullOrEmpty()]
        [System.String] $AppFolder = "VcRedists",

        [Parameter(Mandatory = $False, Position = 1)]
        [ValidatePattern('^[a-zA-Z0-9]+$')]
        [System.String] $MdtDrive = "DS001",

        [Parameter(Mandatory = $False, Position = 2)]
        [ValidatePattern('^[a-zA-Z0-9]+$')]
        [System.String] $Publisher = "Microsoft",

        [Parameter(Mandatory = $False, Position = 3)]
        [ValidatePattern('^[a-zA-Z0-9\+ ]+$')]
        [System.String] $BundleName = "Visual C++ Redistributables",

        [Parameter(Mandatory = $False, Position = 4)]
        [ValidatePattern('^[a-zA-Z0-9-]+$')]
        [System.String] $Language = "en-US"
    )

    # If running on PowerShell Core, error and exit.
    If (Test-PSCore) {
        Write-Warning -Message "$($MyInvocation.MyCommand): PowerShell Core doesn't support PSSnapins. We can't load the MicrosoftDeploymentToolkit module."
        Throw [System.Management.Automation.InvalidPowerShellStateException]
        Exit
    }

    # Import the MDT module and create a PS drive to MdtPath
    If (Import-MdtModule) {
        If ($pscmdlet.ShouldProcess($Path, "Mapping")) {
            try {
                New-MdtDrive -Drive $MdtDrive -Path $MdtPath -ErrorAction SilentlyContinue | Out-Null
                Restore-MDTPersistentDrive -Force | Out-Null
            }
            catch [System.Exception] {
                Write-Warning -Message "$($MyInvocation.MyCommand): Failed to map drive to [$MdtPath]."
                Throw $_.Exception.Message
                Exit
            }
        }
    }
    Else {
        Write-Warning -Message "$($MyInvocation.MyCommand): Failed to import the MDT PowerShell module. Please install the MDT Workbench and try again."
        Throw [System.Management.Automation.InvalidPowerShellStateException]
        Exit
    }

    # Get properties from the existing bundle/s
    try {
        $gciParams = @{
            Path        = "$($MdtDrive):\Applications"
            Include     = "$Publisher $BundleName"
            Recurse     = $True
            ErrorAction = "SilentlyContinue"
        }
        $Bundles = Get-ChildItem @gciParams | Where-Object { $_.CommandLine -eq "" }
        #Write-Verbose -Message "$($MyInvocation.MyCommand): Bundle is: $($bundle.PSPath)"
    }
    catch [System.Exception] {
        Write-Warning -Message "$($MyInvocation.MyCommand): Failed to retreive the existing Visual C++ Redistributables bundle."
        Throw $_.Exception.Message
        Exit
    }

    # Grab the Visual C++ Redistributable application guids; Sort added VcRedists by version so they are ordered correctly
    $target = "$($MdtDrive):\Applications\$AppFolder"
    Write-Verbose -Message "$($MyInvocation.MyCommand): Gathering VcRedist applications in: $target"
    $existingVcRedists = Get-ChildItem -Path $target | `
        Where-Object { ($_.Name -like "*Visual C++*") -and ($_.guid -ne $bundle.guid) -and ($_.CommandLine -ne "") }
    $existingVcRedists = $existingVcRedists | Sort-Object -Property Version
    $dependencies = @(); ForEach ($app in $existingVcRedists) { $dependencies += $app.guid }

    ForEach ($bundle in $Bundles) {
        If ($PSCmdlet.ShouldProcess($bundle.PSPath, "Update dependencies")) {
            try {
                $sipParams = @{
                    Path        = ($bundle.PSPath.Replace($bundle.PSProvider, "")).Trim(":")
                    Name        = "Dependency"
                    Value       = $dependencies
                    ErrorAction = "SilentlyContinue"
                    Force       = $True
                }
                Set-ItemProperty @sipParams | Out-Null
            }
            catch [System.Exception] {
                Write-Warning -Message "$($MyInvocation.MyCommand): Error updating VcRedist bundle dependencies."
                Throw $_.Exception.Message
                Continue
            }
        }
        If ($PSCmdlet.ShouldProcess($bundle.PSPath, "Update version")) {
            try {
                $sipParams = @{
                    Path        = ($bundle.PSPath.Replace($bundle.PSProvider, "")).Trim(":")
                    Name        = "Version"
                    Value       = (Get-Date -format "yyyy-MMM-dd")
                    ErrorAction = "SilentlyContinue"
                    Force       = $True
                }
                Set-ItemProperty @sipParams | Out-Null
            }
            catch [System.Exception] {
                Write-Warning -Message "$($MyInvocation.MyCommand): Error updating VcRedist bundle version."
                Throw $_.Exception.Message
                Continue
            }
        }
        
        # Write the bundle to the pipeline
        Write-Output -InputObject ($bundle | Select-Object -Property * )
    }
}
