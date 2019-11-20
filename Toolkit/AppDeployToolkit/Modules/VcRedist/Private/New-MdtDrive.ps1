Function New-MdtDrive {
    <#
        .SYNOPSIS
            Creates a new persistent PS drive mapped to an MDT share.

        .NOTES
            Author: Aaron Parker
            Twitter: @stealthpuppy

        .PARAMETER Path
            A path to a Microsoft Deployment Toolkit share.

        .PARAMETER Drive
            A PS drive letter to map to the MDT share.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.String])]
    Param (
        [Parameter(Mandatory = $False, Position = 0, ValueFromPipeline = $True)]
        [ValidateNotNullOrEmpty()]
        [System.String] $Drive = "DS009",

        [Parameter(Mandatory = $True, Position = 1, ValueFromPipeline = $True)]
        [ValidateNotNullOrEmpty()]
        [System.String] $Path
    )
    $description = "MDT drive created by $($MyInvocation.MyCommand)"
    If ($mdtDrives = Get-MdtPersistentDrive | Where-Object { ($_.Path -eq $Path) -and ($_.Description -eq $Description) }) {
        Write-Verbose "$($MyInvocation.MyCommand): Found MDT drive: $($mdtDrives[0].Name)"
        $output = $mdtDrives[0].Name
    }
    Else {
        If ($pscmdlet.ShouldProcess("$($Drive): to $($Path)", "Mapping")) {
            try {
                New-PSDrive -Name $Drive -PSProvider "MDTProvider" -Root $Path `
                    -NetworkPath $Path -Description $description | Add-MDTPersistentDrive
                $psDrive = Get-MdtPersistentDrive | Where-Object { ($_.Path -eq $Path) -and ($_.Name -eq $Drive) }
            }
            catch [System.Exception] {
                Write-Warning -Message "$($MyInvocation.MyCommand): Failed to create MDT drive at: [$Path]."
                Throw $_.Exception.Message
                Continue
            }
            finally {
                Write-Verbose "$($MyInvocation.MyCommand): Found: $($psDrive.Name)"
                $output = $psDrive.Name
            }
        }
    }
    Write-Output -InputObject $output
}
