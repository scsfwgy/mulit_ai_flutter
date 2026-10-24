param(
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$BuildNumber,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [string]$SourceDir = (Join-Path $PSScriptRoot '../build/windows/x64/runner/Release')
)

$ErrorActionPreference = 'Stop'
$SourceDir = (Resolve-Path $SourceDir).Path
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path
foreach ($relative in @('mulit_ai_flutter.exe', 'flutter_windows.dll', 'data/icudtl.dat')) {
    if (-not (Test-Path (Join-Path $SourceDir $relative))) {
        throw "Incomplete Windows bundle: $relative"
    }
}

$compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($compiler) {
    $iscc = $compiler.Source
} else {
    $iscc = Get-ChildItem "${env:ProgramFiles(x86)}/Inno Setup */ISCC.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $iscc) {
    throw 'Install Inno Setup first (choco install innosetup --yes --no-progress).'
}

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('ai-link-setup-' + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $runtime = Join-Path $temporary 'vc_redist.x64.exe'
    Invoke-WebRequest 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $runtime
    $signature = Get-AuthenticodeSignature $runtime
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw 'Microsoft Visual C++ Runtime signature verification failed.'
    }
    $installer = Join-Path $OutputDir "AI-Link-Setup-$Version+$BuildNumber.exe"
    if (Test-Path $installer) { Remove-Item $installer -Force }
    & $iscc "/DAppVersion=$Version" "/DBuildNumber=$BuildNumber" "/DSourceDir=$SourceDir" "/DOutputDir=$OutputDir" "/DRuntimePath=$runtime" (Join-Path $PSScriptRoot '../windows/installer/ai-link.iss')
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $installer)) {
        throw 'Windows installer compilation failed.'
    }
    Write-Host "Windows installer: $installer"
} finally {
    Remove-Item $temporary -Recurse -Force
}
