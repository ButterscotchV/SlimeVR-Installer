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
        Write-Output "Checking for ""$FileName""..."

        # Use HttpWebRequest to download file
        $WebRequest = [System.Net.HttpWebRequest]::Create($Uri);

        # If the file already exists
        if (Test-Path "$OutFile") {
            # Then add last modified info
            $WebRequest.IfModifiedSince = $FileInfo.LastWriteTime
        }

        $WebRequest.Method = "HEAD";
        [System.Net.HttpWebResponse]$WebResponse = $WebRequest.GetResponse()

        Write-Output "Downloading ""$FileName"" ($($WebResponse.ContentLength) bytes)..."

        # Download the file using a simpler method
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile

        # Write the last modified time from the request
        $FileInfo.LastWriteTime = $WebResponse.LastModified

        Write-Output """$FileName"" has been downloaded"
    }
    catch [System.Net.WebException] {
        # Check for a 304 error (file not modified)
        if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotModified) {
            Write-Output """$FileName"" is not modified, not downloading..."
        }
        else {
            # Unexpected error
            $Status = $_.Exception.Response.StatusCode
            $Msg = $_.Exception
            Write-Output "Error dowloading ""$FileName"", Status code: $Status - $Msg"
        }
    }
}

# Use download directory from environment variables, otherwise default to working directory
$DestDir = New-Item (& { $Env:WINDOWS_OFFLINE_FILES_DIR ?? "offline-files" }) -ItemType directory -Force
Write-Output "Output directory set to ""$DestDir"""

$ServerVersion = "v0.16.3"
$JavaVersion = "17.0.15+6"
$DriverVersion = "v0.3.1"
$FeederVersion = "v0.2.11"

$JavaMajorVersion = $JavaVersion.Split(".")[0]
$JavaFileName = "OpenJDK${JavaMajorVersion}U-jre_x64_windows_hotspot_$($JavaVersion -Replace "\+", "_").zip"

$SharedDir = New-Item (Join-Path $DestDir "versions") -ItemType directory -Force

$ServerDir = New-Item (Join-Path $SharedDir "server") -ItemType directory -Force
$WebView2Dir = New-Item (Join-Path $SharedDir "webview2") -ItemType directory -Force
$JavaDir = New-Item (Join-Path $SharedDir "java") -ItemType directory -Force
$DriverDir = New-Item (Join-Path $SharedDir "driver") -ItemType directory -Force
$FeederDir = New-Item (Join-Path $SharedDir "feeder") -ItemType directory -Force
$VcredistDir = New-Item (Join-Path $SharedDir "vcredist") -ItemType directory -Force

$ServerVerDir = New-Item (Join-Path $ServerDir $ServerVersion) -ItemType directory -Force
$DriverVerDir = New-Item (Join-Path $DriverDir $DriverVersion) -ItemType directory -Force
$FeederVerDir = New-Item (Join-Path $FeederDir $FeederVersion) -ItemType directory -Force

$ServerFile = Join-Path $ServerVerDir "SlimeVR-win64.zip"
$WebView2File = Join-Path $WebView2Dir "MicrosoftEdgeWebView2RuntimeInstaller.exe"
$JavaFile = Join-Path $JavaDir $JavaFileName
$DriverFile = Join-Path $DriverVerDir "slimevr-openvr-driver-win64.zip"
$FeederFile = Join-Path $FeederVerDir "SlimeVR-Feeder-App-win64.zip"
$VcredistFile = Join-Path $VcredistDir "vc_redist.x64.exe"

$ServerUrl = "https://github.com/ButterscotchV/SlimeVR-Server/releases/download/$ServerVersion/SlimeVR-win64.zip"
$WebView2Url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
$JavaUrl = "https://github.com/adoptium/temurin${JavaMajorVersion}-binaries/releases/download/jdk-$($JavaVersion -Replace "\+", "%2B")/$JavaFileName"
$DriverUrl = "https://github.com/SlimeVR/SlimeVR-OpenVR-Driver/releases/download/$DriverVersion/slimevr-openvr-driver-win64.zip"
$FeederUrl = "https://github.com/SlimeVR/SlimeVR-Feeder-App/releases/download/$FeederVersion/SlimeVR-Feeder-App-win64.zip"
$VcredistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"

Get-File-From-Uri -Uri $ServerUrl -OutFile $ServerFile
Get-File-From-Uri -Uri $WebView2Url -OutFile $WebView2File
Get-File-From-Uri -Uri $JavaUrl -OutFile $JavaFile
Get-File-From-Uri -Uri $DriverUrl -OutFile $DriverFile
Get-File-From-Uri -Uri $FeederUrl -OutFile $FeederFile
Get-File-From-Uri -Uri $VcredistUrl -OutFile $VcredistFile

Write-Output "Copying downloaded files to output directory..."
Copy-Item @($JavaFile, $WebView2File, $ServerFile, $DriverFile, $FeederFile, $VcredistFile) $DestDir -Force

Write-Output "Generating installer manifest..."
$BaseFolder = $Env:WINDOWS_WEB_DIR ?? "."
Set-Content -Path (Join-Path $BaseFolder "installer_manifest.txt") @"
### Versions
- Server $ServerVersion ($ServerUrl)
- Driver $DriverVersion ($DriverUrl)
- Feeder-App $FeederVersion ($FeederUrl)
- Java $JavaVersion-jre ($JavaUrl)
- WebView2 [online installer, exe included] ($WebView2Url)
- Microsoft Visual C++ Redistributable ($VcredistUrl)

### Workflow run
$($Env:GH_RUN_URL)

### Mirror links

### Hashes

### Notes
For your own safety, you can pass the installer through VirusTotal at https://www.virustotal.com/
"@
