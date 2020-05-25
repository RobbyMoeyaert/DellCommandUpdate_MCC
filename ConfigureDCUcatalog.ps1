<#

.SYNOPSIS 
ConfigureDCUcatalog.ps1

Author: Robby Moeyaert

.DESCRIPTION 
This script configures the Catalog.xml file for Dell Command Update. It expects to be run from the directory where the folders and ZIP files of the catalog files are placed.
The script will modify the Catalog.xml file with the Microsoft Connected Cache server path to use as local repository.
The expectation is that the MCC server has been modified to allow the downloads to work.

Please refer to the README file at
https://github.com/RobbyMoeyaert/DellCommandUpdate_MCC/blob/master/README.md

#>

param
(
   [String]$LogFile = "$env:TEMP\ConfigureDCUcatalog.log",
   [switch]$Pilot,
   [String]$CatalogTargetLocation = "$env:ProgramData\Dell\UpdateService"
)

#Detect if we're running as a 32bit process on a 64bit system
$ScriptPath = $MyInvocation.MyCommand.Definition

if([Environment]::Is64BitOperatingSystem) {
    if(!([Environment]::Is64BitProcess) ) {
        #64bit system but 32bit process!!! must restart in 64bit mode
        [String[]]$ar = "-NoProfile", "-NoLogo", "-File", "`"$ScriptPath`""

        #append named parameters as they are not included in $args
        $ar = $ar + "-Logfile $LogFile"
        if($Pilot) {
            $ar = $ar + "-Pilot"
        }
        $ar = $ar + "-CatalogTargetLocation $CatalogTargetLocation"

        #append any arguments in $args
        if($args -ne $null) {
            $ar = $ar + $args #append argument list if exists
        }

        #start 64bit powershell with all the same script parameters as the current 32bit powershell
        $proc = Start-Process "$env:systemroot\sysnative\windowspowershell\v1.0\powershell.exe" $ar -Wait -NoNewWindow -PassThru
        $proc.WaitForExit()
        $exitcode = $proc.ExitCode
        #immediately exit the 32bit powershell with whaver exitcode 64bit powershell gave
        Exit $exitcode
    }
}

Start-Transcript -Path $LogFile

#==================================================================================================================================
#script variables
#==================================================================================================================================
#$DebugPreference = "SilentlyContinue" # disables debugging
$DebugPreference = "Continue"  # enables debugging
$Script:Name = $MyInvocation.MyCommand.Name
$Script:CurDir = Split-Path $MyInvocation.MyCommand.Definition -parent
$Script:Version = "1.0.0"


#==================================================================================================================================
#exit codes
#==================================================================================================================================
$ERR_Success = 0
$ERR_AdminRights = 50
$ERR_DCUNotFound = 100
$ERR_CatalogNotFound = 101

#==================================================================================================================================
# Generic Functions
#==================================================================================================================================

Function CheckAdminRights {
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] “Administrator”)) {
        Write-Host "ERROR: This script must be run with Administrator privileges"
        ExitWithCode $ERR_AdminRights
    }

}

#==================================================================================================================================
# Script Functions
#==================================================================================================================================

Function IsPilot {
    $return = $false
    
    #if there are ways you can locally detect that a machine is a pilot machine, enter the script logic here
    #examples would include a registry value set via script or GPO
    #this is optional, you can also just use the -Pilot parameter instead, or combine both

    return $return
}


#==================================================================================================================================
# Main Script
#==================================================================================================================================

#Check that we're running as a user that has Administrator privileges
CheckAdminRights

$xmlFileName = $null
$DCUcli = $null

#Look for the Dell Command Update CLI
Write-Host "Looking for Dell Command Update"
$DCUcliAPPX = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe" # APPX DCU location
$DCUcliWin32 = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe" # Win32 DCU location

if(Test-Path $DCUcliAPPX) {
    Write-Host "Found DCU at `"$DCUcliAPPX`""
    $DCUcli = $DCUcliAPPX
} elseif(Test-Path $DCUcliWin32) {
    Write-Host "Found DCU at `"$DCUcliWin32`""
    $DCUcli = $DCUcliWin32
} else {
    Write-Host "Dell Command Update not found, exiting"
    Stop-Transcript
    Exit $ERR_DCUNotFound
}

#Check if the machine is a pilot machine
$isPilot = IsPilot
if($Pilot) {
    #Override if script parameter is set
    $isPilot = $true
}


$ModelName = (gwmi Win32_ComputerSystem).Model
Write-Host "Hardware model is `"$ModelName`""

#Look for catalog
Write-Host "Looking for DCU Catalog ZIP file"
$zipFileName = "CatalogPC.zip"
if($isPilot) {
    $zipFileName = "PilotCatalogPC.zip"
}
$zipFileNameAndPath = $Script:CurDir + "\" + $ModelName + "\" + $zipFileName

if(Test-Path $zipFileNameAndPath) {
    Write-Host "Found model specific Catalog ZIP file at `"$zipFileNameAndPath`""
} else {
    $zipFileNameAndPath = $Script:CurDir + "\" + $zipFileName
    if(Test-Path $zipFileNameAndPath) {
        Write-Host "Found DCU Catalog at `"$zipFileNameAndPath`""
    } else {
        Write-Host "ERROR : cannot find DCU Catalog file ZIP file"
        Stop-Transcript
        Exit $ERR_CatalogNotFound
    }
}

#Remove any leftovers from previous attempts
if(Test-Path "$env:TEMP\DCU") {
    Remove-Item -Path "$env:TEMP\DCU" -Recurse -Force
}

#Unzip into temp
Expand-Archive -Path $zipFileNameAndPath -DestinationPath "$env:TEMP\DCU"

if(Test-Path "$env:TEMP\DCU\CatalogPC.xml") {
    Write-Host "Catalog XML file extracted succesfully"
    $xmlFileName = "$env:TEMP\DCU\CatalogPC.xml"
} else {
    Write-Host "ERROR : Catalog XML file not found after ZIP extract"
    Remove-Item -Path "$env:TEMP\DCU" -Recurse -Force
    Stop-Transcript
    Exit $ERR_CatalogNotFound
}

#Check if Microsoft Connected Cache is configured through GPO or CSP
Write-Host "Looking for MCC server configuration"
$MCCservers = $null
$isMCCConfigured = $false
$MCCserver = ""
#GPO
$MCCservers = Get-ItemPropertyValue -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization -Name DOCacheHost
if($MCCservers -eq $null) {
    #CSP
    $MCCservers = Get-ItemPropertyValue -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeliveryOptimization -Name DOCacheHost
}
if($MCCservers -eq $null) {
    Write-Host "Could not find MCC server configuration"
    $isMCCConfigured = $false
} else {
    Write-Host "Found MCC server configuration : `"$MCCservers`""
    if($MCCservers.Equals("")) {
        Write-Host "Blank value configured, no MCC server is within the boundary of this machine"
        $isMCCConfigured = $false
    } else {
        if($MCCservers.Contains(",")) {
            Write-Host "Multiple MCC servers configured"
            $MCCserverArray = $MCCservers.Split(",")
            #pick a random MCC server from the list
            $rand = Get-Random -Maximum $MCCserverArray.Count
            $MCCserver = $MCCserverArray[$rand]
            Write-Host "Setting MCC server to `"$MCCserver`""
            $isMCCConfigured = $true
        } else {
            Write-Host "Single MCC server configured"
            $MCCserver = $MCCservers
            Write-Host "Setting MCC server to `"$MCCserver`""
            $isMCCConfigured = $true  
        }
    }
}

#Load catalog file
Write-Host "Reading catalog XML file `"$xmlFileName`""

[xml]$xmlDoc = Get-Content $xmlFileName

if($isMCCConfigured) {
    #modify the baseLocation to use the MCC server
    Write-Host "Modifying baseLocation to `"http://$MCCserver/DellDownloads`""
    $xmlDoc.Manifest.baseLocation = "http://$MCCserver/DellDownloads"

    #add the baseLcationAccessProtcols attribute, keeps DCU from complaining in the logs
    Write-Host "Adding attribute `"baseLocationAccessProtocols`" and setting it to `"HTTP`""
    $attribute = $xmlDoc.CreateAttribute("baseLocationAccessProtocols")
    $attribute.Value = "HTTP"
    $xmlDoc.Manifest.Attributes.Append($attribute)
}

$TargetFileName = "$CatalogTargetLocation\DCUCatalog.xml"

#remove existing file
if(Test-Path $TargetFileName) {
    Write-Host "Deleting existing DCUCatalog.xml file"
    Remove-Item $TargetFileName
    if($?) {
        Write-Host "Delete succesful"
    }
}

#write new file
Write-Host "Writing Catalog.xml file : `"$TargetFileName`""
$xmlDoc.Save($TargetFileName)
if($?) {
    Write-Host "Write succesful"
}

#clean up
Remove-Item -Path "$env:TEMP\DCU" -Recurse -Force

#check if DCU was already configured to use this Catalog XML file
Write-Host "Checking if DCU is already configured to use the Catalog.xml file"
$configureDCUcatalog = $false
$DCUcatalogReg = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\DELL\UpdateService\Clients\CommandUpdate\Preferences\Settings\General" -Name "CatalogsPath"
if($DCUcatalogReg -eq $null) {
    Write-Host "DCU does not have a custom catalog file configured, need to configure it"
    $configureDCUcatalog = $true
} else {
    if($DCUcatalogReg.toLower().Contains(($TargetFileName).toLower())) {
        Write-Host "DCU is already configured to use the DCUCatalog.xml file, no need to change"
    } else {
        Write-Host "DCU does not have this specific DCUCatalog.xml file configured, need to configure it"
        $configureDCUcatalog = $true
    }
}

if($configureDCUcatalog) {
    Write-Host "Configuring DCU to use the Catalog.xml file"
    [String[]]$DCUar = "/configure", "-catalogLocation=`"$TargetFileName`""
    $DCUproc = Start-Process $DCUcli $DCUar -Wait -NoNewWindow -PassThru
    $DCUproc.WaitForExit()
    $DCUexitcode = $DCUproc.ExitCode
    Write-Host "Dell Command Update exited with code `"$DCUexitcode`""
}


Write-Host "---"
write-Host "Ending script with return code: $ERR_success"
Stop-Transcript
Exit $ERR_Success