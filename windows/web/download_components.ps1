Function Get-File-From-Uri {
    Param (
        [Parameter(Mandatory)] [System.Uri]$Uri,
        [Parameter(Mandatory)] [string]$OutFile
    )

    # Create a FileInfo object out of the output file for reading and writing information
    [System.IO.FileInfo]$FileInfo = $OutFile
    # FileInfo works even if the file/directory doesn't exist,
    # which is better than Get-Item which requires the file to exist
    $FileName = $FileInfo.Name
    $DirectoryName = $FileInfo.DirectoryName

    # Make sure the destination directory exists
    if (!(Test-Path $DirectoryName)) {
        [void](New-Item $DirectoryName -ItemType directory -Force)
    }

    try {
        Write-Output "Checking for `"$FileName`"..."

        # Use HttpWebRequest to download file
        $WebRequest = [System.Net.HttpWebRequest]::Create($Uri);

        # If the file already exists
        if (Test-Path "$OutFile") {
            # Then add last modified info
            $WebRequest.IfModifiedSince = $FileInfo.LastWriteTime
        }

        $WebRequest.Method = "HEAD";
        [System.Net.HttpWebResponse]$WebResponse = $WebRequest.GetResponse()

        Write-Output "Downloading `"$FileName`" ($($WebResponse.ContentLength) bytes)..."

        # Download the file using a simpler method
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile

        # Write the last modified time from the request
        $FileInfo.LastWriteTime = $WebResponse.LastModified

        Write-Output "`"$FileName`" has been downloaded"
    }
    catch [System.Net.WebException] {
        # Check for a 304 error (file not modified)
        if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotModified) {
            Write-Output "`"$FileName`" is not modified, not downloading..."
        }
        else {
            # Unexpected error
            $Status = $_.Exception.Response.StatusCode
            $Msg = $_.Exception
            Write-Output "Error dowloading `"$FileName`", Status code: $Status - $Msg"
        }
    }
}

$JavaVersion = "17.0.17+10"
$JavaMajorVersion = $JavaVersion.Split(".")[0]
$JavaFileName = "OpenJDK${JavaMajorVersion}U-jre_x64_windows_hotspot_$($JavaVersion -Replace "\+", "_").zip"

$ServerVersion = "v19.0.0"
$DriverVersion = "v4.0.0"
$FeederVersion = "v0.2.15"

# Use download directory from environment variables, otherwise default to working directory
$SharedDir = New-Item (& { $Env:WINDOWS_COMPONENT_CACHE_DIR ?? "component-cache" }) -ItemType directory -Force
Write-Output "File cache set to `"$SharedDir`""

$VcredistDir = New-Item (Join-Path $SharedDir "vcredist") -ItemType directory -Force
$JavaDir = New-Item (Join-Path $SharedDir "java") -ItemType directory -Force
$ServerDir = New-Item (Join-Path $SharedDir "server" $ServerVersion) -ItemType directory -Force
$DriverDir = New-Item (Join-Path $SharedDir "driver" $DriverVersion) -ItemType directory -Force
$FeederDir = New-Item (Join-Path $SharedDir "feeder" $FeederVersion) -ItemType directory -Force

$VcredistFile = Join-Path $VcredistDir "vc_redist.x64.exe"
$JavaFile = Join-Path $JavaDir $JavaFileName
$ServerFile = Join-Path $ServerDir "SlimeVR-win64.zip"
$DriverFile = Join-Path $DriverDir "slimevr-openvr-driver-win64.zip"
$FeederFile = Join-Path $FeederDir "SlimeVR-Feeder-App-win64.zip"

$VcredistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$JavaUrl = "https://github.com/adoptium/temurin${JavaMajorVersion}-binaries/releases/download/jdk-$($JavaVersion -Replace "\+", "%2B")/$JavaFileName"
$ServerUrl = "https://github.com/SlimeVR/SlimeVR-Server/releases/download/$ServerVersion/SlimeVR-win64.zip"
$DriverUrl = "https://github.com/SlimeVR/SlimeVR-OpenVR-Driver/releases/download/$DriverVersion/slimevr-openvr-driver-win64.zip"
$FeederUrl = "https://github.com/SlimeVR/SlimeVR-Feeder-App/releases/download/$FeederVersion/SlimeVR-Feeder-App-win64.zip"

Get-File-From-Uri -Uri $VcredistUrl -OutFile $VcredistFile
Get-File-From-Uri -Uri $JavaUrl -OutFile $JavaFile
Get-File-From-Uri -Uri $ServerUrl -OutFile $ServerFile
Get-File-From-Uri -Uri $DriverUrl -OutFile $DriverFile
Get-File-From-Uri -Uri $FeederUrl -OutFile $FeederFile

Write-Output "Updating NSIS script for offline installation..."
$NsiPath = Join-Path $PSScriptRoot "slimevr_web_installer.nsi"
$content = Get-Content $NsiPath -Raw

function Update-NsiDefine {
    param(
        [string]$Name,
        [string]$Value
    )
    $script:content = $script:content -Replace "(!define\s+$Name\s+)`"[^`"]*`"", "`$1`"$Value`""
}

# Set versions
Update-NsiDefine -Name "JREVersion" -Value $JavaVersion
Update-NsiDefine -Name "SVRServerVersion" -Value $ServerVersion
Update-NsiDefine -Name "SVRDriverVersion" -Value $DriverVersion
Update-NsiDefine -Name "SVRFeederVersion" -Value $FeederVersion

# Set to local
Update-NsiDefine -Name "MVCURLType" -Value "local"
Update-NsiDefine -Name "JREURLType" -Value "local"
Update-NsiDefine -Name "SVRServerURLType" -Value "local"
Update-NsiDefine -Name "SVRDriverURLType" -Value "local"
Update-NsiDefine -Name "SVRFeederURLType" -Value "local"

# Set local paths
Update-NsiDefine -Name "MVCDLURL" -Value $VcredistFile
Update-NsiDefine -Name "JREDLURL" -Value $JavaFile
Update-NsiDefine -Name "SVRServerDLURL" -Value $ServerFile
Update-NsiDefine -Name "SVRDriverDLURL" -Value $DriverFile
Update-NsiDefine -Name "SVRFeederDLURL" -Value $FeederFile

# Set Java ZIP name (it contains a version number)
Update-NsiDefine -Name "JREDLFileZip" -Value $JavaFileName

# Set the output file
$VersionTag = $ServerVersion -Replace "v", ""
$content = $content -Replace "slimevr_web_installer.exe", "slimevr_${VersionTag}_offline_installer.exe"

Set-Content -Path $NsiPath -Value $content -Encoding UTF8

Write-Output "Generating installer manifest..."
$BaseFolder = $Env:WINDOWS_WEB_DIR ?? "."
Set-Content -Path (Join-Path $BaseFolder "slimevr_${VersionTag}_offline_installer.txt") @"
### Dependencies
- Microsoft Visual C++ Redistributable ($VcredistUrl)
- Java $JavaVersion-jre ($JavaUrl)

### Components
- Server $ServerVersion ($ServerUrl)
- Driver $DriverVersion ($DriverUrl)
- Feeder-App $FeederVersion ($FeederUrl)

### Workflow run
$($Env:GH_RUN_URL)

### Hashes

### Notes
For your own safety, you can pass the installer through VirusTotal at https://www.virustotal.com/
"@
