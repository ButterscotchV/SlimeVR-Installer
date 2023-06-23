$Crc32Alg = Add-Type @"
[DllImport("ntdll.dll")]
public static extern uint RtlComputeCrc32(uint dwInitial, byte[] pData, int iLen);
"@ -Name Crc32Alg -PassThru

function Get-Crc32 {
    Param(
        [Parameter(Mandatory)] [string]$Path
    )
    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    return "{0:X8}" -f ($Crc32Alg::RtlComputeCrc32(0, $Bytes, $Bytes.Length))
}

# Define the paths
$BaseFolder = $Env:WINDOWS_WEB_DIR ?? "."
$FileToHash = Join-Path $BaseFolder "slimevr_web_installer.exe"
$ManifestFile = Join-Path $BaseFolder "installer_manifest.txt"

# Compute the hashes
$Md5 = (Get-FileHash -Path $FileToHash -Algorithm MD5).Hash
$Sha1 = (Get-FileHash -Path $FileToHash -Algorithm SHA1).Hash
$Sha256 = (Get-FileHash -Path $FileToHash -Algorithm SHA256).Hash
$Crc32 = Get-Crc32 $FileToHash

$hashList = @"
### Hashes
- MD5: $Md5
- SHA1: $Sha1
- SHA256: $Sha256
- CRC32: $Crc32
"@

$FileContent = (Get-Content -Path $ManifestFile -Raw) -replace "# Hashes", $hashList
Set-Content -Path $ManifestFile $FileContent

Write-Output @"
Hashes have been computed and updated in the installer manifest:
$FileContent
"@
