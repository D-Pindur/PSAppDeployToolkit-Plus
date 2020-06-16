# Bootstrap script for PSADT+
# Tested and designed for Datto RMM
# Version 2.2.1.0

# REQUIRED PSADT files
$psadtArchiveUri = ${Env:\PSADT_ArchiveURI}
$psadtArchive = 'PSAppDeployToolkit.zip'
$psadtExtrasUri = ${Env:\PSADT_ExtrasURI}
$psadtExtras = 'Extras.zip'
$psadtSettings = 'Deploy-Application.json'
# OPTIONAL PSADT files
$psadtBanner = 'AppDeployToolkitBanner.png'
$psadtScript = 'Deploy-Application.ps1'
$psadtSupport = 'SupportFiles.zip'
$psadtFiles = 'Files.zip'
$psadtCustomUri = ${Env:\PSADT_CustomURI}
$psadtCustom = 'Custom.zip'


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

If ( (-Not (Test-Path $psadtArchive) ) -and ($psadtArchiveUri) ) {
    Write-Output ('Downloading ' + $psadtArchiveUri)
    Invoke-WebRequest -Uri $psadtArchiveUri -OutFile $psadtArchive
}

If ($psadtExtrasUri) {
    Write-Output ('Downloading ' + $psadtExtrasUri)
    Invoke-WebRequest -Uri $psadtExtrasUri -OutFile $psadtExtras
}

If ($psadtCustomUri) {
    Write-Output ('Downloading ' + $psadtCustomUri)
    Invoke-WebRequest -Uri $psadtCustomUri -OutFile $psadtCustom
}

# Set temporary directory; Deploy-Application.exe doesn't work if # in the actual
# component subdirectory (C:\ProgramData\CentraStage\Packages\{GUID}#)
$installerDir = 'C:\ProgramData\PSAppDeployToolkit\InstallerTemp'
$psadtPath = ($installerDir + '\AppDeployToolkit')
$psadtExtrasPath = ($psadtPath + '\Extras')
$psadtSupportPath = ($installerDIr + '\SupportFiles')
$psadtFilesPath = ($installerDIr + '\Files')

# Runs PsExec.exe with -i so PSADT has more magic
$psExecPath = ($psadtPath + '\Extras\PsExec.exe')
# C:\Program Files\Microsoft Deployment Toolkit\Templates\Distribution\Tools\{x86,x64}
$serviceUIPath = ($psadtPath + '\Extras\ServiceUI.exe')
$psExecArgs = '-s -i -accepteula -nobanner "'

# Remove installation directory to ensure old installations don't cause issues
# This might happen if a previous install did exit cleanly
if (Test-Path $installerDir) {
    Write-Warning ('Previous ' + $installerDir + ' found. Attempting force delete.')
    Remove-Item -Path $installerDir -Force -Recurse
}

# Creates the Files and SupportFiles directories in case the archive does not have them
# (Windows' built-in archive management won't add empty directories but 7-Zip does..)
@($psadtFilesPath, $psadtSupportPath, $psadtExtrasPath) | ForEach-Object -Process {
    If ( -not (Test-Path -Path $PSItem) ) {
        Write-Output ('Creating directory: '+ $PSItem)
        New-Item -Path $PSItem -ItemType Directory -Force | Out-Null
    }
}

foreach ($psadtItem in @($psadtArchive,$psadtExtras,$psadtCustom,$psadtSettings,$psadtBanner,$psadtScript,$psadtSupport,$psadtFiles)) {
    If (Test-Path -Path $psadtItem) {
        Switch -exact ($psadtItem) {
            $psadtArchive { Expand-Archive -Path $psadtArchive -DestinationPath $installerDir -Force }
            $psadtExtras { Expand-Archive -Path $psadtExtras -DestinationPath $psadtExtrasPath -Force }
            $psadtCustom { Expand-Archive -Path $psadtCustom -DestinationPath $psadtPath -Force }
            $psadtSettings {Copy-Item -Path $psadtSettings -Destination $installerDir -Force}
            $psadtBanner {Copy-Item -Path $psadtBanner -Destination $psadtPath -Force}
            $psadtScript {Copy-Item -Path $psadtScript -Destination $installerDir -Force}
            $psadtSupport {Expand-Archive -Path $psadtSupport -DestinationPath $psadtSupportPath -Force}
            $psadtFiles {Expand-Archive -Path $psadtFiles -DestinationPath $psadtFilesPath -Force}
        }
        Write-Output ($psadtItem + ' was found')
    }
    else {
        Write-Warning ($psadtItem + ' not found')
        If (($psadtItem -like $psadtArchive) -or ($psadtItem -like $psadtSettings) -or ($psadtItem -like $psadtExtras)) {
            Write-Error ($psadtItem + ' is a required file. Exiting.')
            Exit -1
        }
    }
}

# Export needed RMM Environment Variables to JSON for use in PSADT
$deploymentSettings = Get-Content -Path $psadtSettings | ConvertFrom-Json
if ($deploymentSettings.rmmVariables) {
    Write-Output ('Attempting export of ' + ($deploymentSettings.rmmVariables -Join ',') + ' variables to JSON file.')
    $rmmEnv = New-Object -TypeName psobject
    $deploymentSettings.rmmVariables | ForEach-Object -Process {
        # Check for same Variable with "or" prefix for override from component (vs inherited from site or account level)
        $override = ('Env:or' + $PSItem)
            If (Test-Path -Path $override) {
                Write-Information -MessageData (${Env:$PSItem} + ' found as an override variable')
                $envVar = (Get-Item -Path $override | Select-Object -Property Name,Value)
            }
            else {
                if ( Test-Path -Path ('Env:\' + $PSItem) ) {
                    Write-Information -MessageData (('Env:\' + $PSItem) + ' found as a site or account variable')
                    $envVar = (Get-Item -Path ('Env:\' + $PSItem) | Select-Object -Property Name,Value)
                    $rmmEnv | Add-Member -MemberType NoteProperty -Name $envVar.Name -Value $envVar.Value
                }
                else {
                    Write-Warning -Message ($PSItem + ' not found in site variables.')
                }
            }
    }
        $rmmEnv | ConvertTo-Json | Out-File -FilePath ($psadtSupportPath + '\rmmEnv.json')
}

# Checking and setting options for INSTALL vs UNINSTALL
if (Test-Path ("Env:\Action")) {
    Switch -exact (${Env:\Action})
    {
        'INSTALL' {
            Write-Output ('Action set for INSTALL')
            $psadtType = '-DeploymentType \"Install\"'
        }
        'UNINSTALL' {
            Write-Output ('Action set for UNINSTALL')
            $psadtType = '-DeploymentType \"Uninstall\"'
        }
        default {
            # In case the action variable was created incorrectly
            Write-Error -Message ('Unknown action: ' + ${Env:\Action})
            Exit -1
        }
    }
} else {
    # In case the action was not created in the component, set action to INSTALL
    # (Also helps running directly from a PowerShell prompt to test install)
    Write-Output 'Missing "Action" command. Defaulting to INSTALL.'
    $psadtType = '-DeploymentType \"Install\"'
}

# Check for user session to push notifications and dialogs
# Sets installation program and parameters
if ((Get-WmiObject -Class win32_computersystem).UserName) {
    Write-Output ('User session found.')
    $psadtMode = '-DeployMode \"Interactive\"'
    # Adding ServiceUI.exe to interact with the user session
    $psExecArgs = ($psExecArgs + $serviceUIPath + '" -process:explorer.exe "')
} else {
    Write-Output ('User session not found.')
    $psadtMode = '-DeployMode \"NonInteractive\"'
}

# Setup complete commandline arguments to pass to PsExec.exe
$psExecArgs = ($psExecArgs + $installerDir + '\Deploy-Application.exe" "' + $psadtType + ' ' + $psadtMode + '"')

# Beings the installtion Program
if (Test-Path $psExecPath) {
    Write-Output ('Starting installer program with the command: ' + $psExecPath + ' ' + $psExecArgs)
    Start-Process -FilePath $psExecPath -ArgumentList $psExecArgs -WorkingDirectory $installerDir -Wait
    }
else {
    Write-Warning ('Running installer failed. ' + $psExecPath + ' not found')
    Exit -1
}

# Get log from PSADT and dump to stdout for RMM
# By default, PSADT log files are saved to $envWinDir\Logs\Software which doesn't exist here
# Even if it did, since the logs are read and deleted by default, it would interfere with non-PSADT logs
# Recommended to change location to ${Env:WINDIR}\Logs\Software\PSAppDeployToolkit and log type to Legacy
[xml]$psadtConfigXml = Get-Content -Path ($psadtPath + '\AppDeployToolkitConfig.xml')
$psadtLogPath = $ExecutionContext.InvokeCommand.ExpandString($psadtConfigXml.AppDeployToolkit_Config.Toolkit_Options.Toolkit_LogPath)
Write-Output ('PASADT Log file location: ' + $psadtLogPath)
$msiLogPath = $ExecutionContext.InvokeCommand.ExpandString($psadtConfigXml.AppDeployToolkit_Config.MSI_Options.MSI_LogPath)
Write-Output ('MSI Log file location: ' + $msiLogPath)
$psadtLogFiles = @()

If ($psadtLogPath -ne $msiLogPath) {
    If (Test-Path ($msiLogPath)) {
        $psadtLogFiles += (Get-ChildItem -Path $msiLogPath -Filter '*.log')
    }
    else {
        Write-Error ('Unable to retreive MSI log directory.')
    }
}

If (Test-Path ($psadtLogPath)) {
    $psadtLogFiles = (Get-ChildItem -Path $psadtLogPath -Filter '*.log')
    $psadtLogFiles | ForEach-Object -Process { Write-Output ('Log file found: ' + $psadtLogFiles) }
    $psadtLogFiles | ForEach-Object -Process {
        If (Test-Path ($PSItem.FullName)) {
            Write-Output ('')
            Write-Output ('*******************************************************************************')
            Write-Output ('*******************************************************************************')
            Write-Output (Split-Path -Path $PSItem.FullName -Leaf)
            Write-Output ('*******************************************************************************')
            Write-Output ('*******************************************************************************')
            Write-Output ('')
            Get-Content -Path ($PSItem.FullName)
            # Comment below to retain logs.
            Remove-Item -Path ($PSItem.FullName)
        }
        else {
            Write-Error ('Unable to read logfile.')
        }
    }
} else {
    Write-Error ('Unable to retreive log directory.')
}

# Get exitcode JSON from PSADT
If (Test-Path ($psadtSupportPath + '\exitCode.json')) {
    $psadtExitCode = (Get-Content -Path ($psadtSupportPath + '\exitCode.json') | ConvertFrom-Json)
}

# Clean-up temporary installation directory
if (Test-Path $installerDir) {
    Write-Output ('')
    Write-Output ('*******************************************************************************')
    Write-Output ('Removing temporary installation directory.')
    Remove-Item -Path $installerDir -Force -Recurse
}

if ($psadtExitCode) {
    Write-Output ('Exiting: ' + $psadtExitCode)
    Exit $psadtExitCode
}