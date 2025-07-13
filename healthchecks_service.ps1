 <# 
.Synopsis
Creates a service to check in with healthchecks once a minute.
.NOTES
===========================================================================
Created by:    Bo Saurage
Created on:    2020-11-03
Filename:      healthchecks_service.ps1
Organization:  
.DESCRIPTION
===========================================================================
Downloads NSSM, installs it. You provide your healthchecks API key, a request is made for a unique url.
A ps1 file is written to disk and a service is set up to run this at an interval of your choosing.
Finally you get to open the checks webpage where you enable notifications.

To list active NSSM services:
Get-WmiObject Win32_Service | Where-Object { $_.PathName -match "nssm.exe" } | Select-Object Name, DisplayName, State, PathName
To remove 
sc.exe delete "healthchecks"
.LINK
https://healthchecks.io/
.INPUTS

#>

#Elevate to Administrator
param([switch]$Elevated)

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if ((Test-Admin) -eq $false) {
    if ($elevated) {
        # tried to elevate, did not work, aborting
    }
    else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
    }
    exit
}
#'running with full privileges'

# Create temp with zip extension (or Expand will complain)
$hc_url_script = $Env:Programfiles + "\healthchecks.ps1"
$url = "https://nssm.cc/release/nssm-2.24.zip"
Add-Type -AssemblyName PresentationFramework


# Download and install NSSM
try {
    $tmp = New-TemporaryFile | Rename-Item -NewName { $_ -replace 'tmp$', 'zip' } -PassThru
    #download
    Invoke-WebRequest -OutFile $tmp $url
    #exract to same folder 
    $tmp | Expand-Archive -DestinationPath $Env:Programfiles -Force
    # remove temporary file
    Get-ChildItem -Path $tmp
    $tmp | Remove-Item
}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Write-Output $ErrorMessage $FailedItem
    Break 
}

#Ask for API key
#$hc_api_key_secure = Read-Host 'Enter your HC API key:' -AsSecureString
#$hc_api_key  = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($hc_api_key_secure))
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
$hc_api_key = [Microsoft.VisualBasic.Interaction]::InputBox("Enter your HC API key", "HC API key", "FFfjTTMdiCcSAMPLEwfExfQjhX9f38fGh")

#Ask for tags
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
$hc_tag = [Microsoft.VisualBasic.Interaction]::InputBox("Enter tag(s) separated by spaces", "HC tags", "server")

#Ask for peroidicity e.g. how often to ping the mothership
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
$hc_timeout = [Microsoft.VisualBasic.Interaction]::InputBox("How often should it call in? (seconds)", "Peroidicity", "60")

#Ask for grace time
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
$hc_grace = [Microsoft.VisualBasic.Interaction]::InputBox("When a check is late, how long to wait until an alert is sent? (seconds)", "Gracetime", "300")

try {
    # Create a new check and copy its url
    $Body = @{
        api_key = $hc_api_key
        name    = $env:computername
        tags    = $hc_tag
        desc    = "Created with healthchecks_service.ps1"
        timeout = $hc_timeout -as [int]
        grace   = $hc_grace -as [int]
    }
 
    $Parameters = @{
        Method      = "POST"
        Uri         = "https://healthchecks.io/api/v1/checks/"
        Body        = ($Body | ConvertTo-Json) 
        ContentType = "application/json"
    }
    $request = Invoke-RestMethod @Parameters
    $hc_url = $request.ping_url
}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Write-Output $ErrorMessage $FailedItem
    Break
}

#Scriptfile to be written to disk and run
try {
    "# run a loop
while(`$true){
  # do a request
  if(!(Invoke-WebRequest $hc_url)){
    # if it can't ping / connect, restart service
    #Restart-Service `$service_name -Force 
  }
  # wait $hc_timeout seconds and then test again if ping / connect is ok
  start-sleep -Seconds $hc_timeout
} 

" | Out-File $hc_url_script
}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Write-Output $ErrorMessage $FailedItem
    Break
}



#Create a Windows serive
Try {
    $NSSMPath = (Get-Command "C:\Program files\nssm-2.24\win64\nssm.exe").Source
    $NewServiceName = "healthchecks"
    $PoShPath = (Get-Command powershell).Source
    $PoShScriptPath = "`"$hc_url_script`""
    $args1 = '-ExecutionPolicy Bypass -NoProfile -File "{0}"' -f $PoShScriptPath
    & $NSSMPath install $NewServiceName $PoShPath $args1
    & $NSSMPath set $NewServiceName Description Ping HealthyChecks once a minute
    & $NSSMPath start $NewServiceName

    #& $NSSMPath status $NewServiceName
}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Write-Output $ErrorMessage $FailedItem
    Break
}

#Get status on service
Try {
    $hc_service_status = Get-Service "healthchecks" -ErrorAction Stop
}
Catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Write-Output $ErrorMessage $FailedItem
  
}
if ($hc_service_status.Status -eq "Running") {
    Write-Output "Super, service is up and running."
}
else {
    Write-Output "Service not running!!!" + $ErrorMessage
}

#Show results
$wshell = New-Object -ComObject Wscript.Shell
$wshell.Popup("Operation Completed `n`n Service is " + $hc_service_status.Status + " `n on " + $env:computername + "`n Every " + $hc_timeout / 60 + "mins it pings " + $hc_url + "`n Tags for this check: " + $hc_tag.ToUpper(), 0, "Done", 0x1)

# Offer to launch webpage to finalize the settings for the check 
$msgBoxInput = [System.Windows.MessageBox]::Show('Open webpage to enable notifications for check?', 'Open browser?', 'YesNo', 'Question')
switch ($msgBoxInput) {
    'Yes' {
        #Launch browser
        $hc_id = $hc_url -replace 'https://hc-ping.com/', ''
        $hc_check_url = "https://healthchecks.io/checks/" + $hc_id + "/details/"
        Invoke-Expression "cmd.exe /C start $hc_check_url"
    }
    'No' {
        #Ok...
        [System.Windows.MessageBox]::Show('Make sure your notifications are set up as desired for checks.', 'Last warning', 'OK', 'Exclamation')
    }
    'Cancel' {
        # Do something
    }
}
exit  
