# Setup MSVC Environment Variables

param(
    [string]$Arch = "x64",
    [string]$Sdk = "",
    [string]$ToolSet = "",
    [string]$VsVersion = "latest"
)

$arch = $Arch
if (-not $arch) {
    $arch = "x64"
}

$vsversion = $VsVersion
if (-not $vsversion) {
    $vsversion = "latest"
}
switch ($vsversion) {
    "2017" { $vsversion = "[15.0,16.0)" }
    "2019" { $vsversion = "[16.0,17.0)" }
    "2022" { $vsversion = "[17.0,18.0)" }
    "2026" { $vsversion = "[18.0,19.0)" }
}
if ($vsversion -match "^(\d+)(\.\d)?$") {
    $max = ([int]$matches[1] + 1)
    $vsversion = "[$vsversion,$max)"
}
# Write-Host "::notice::vsversion = `"$vsversion`""

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
# Write-Host "::notice::vswhere = [$vswhere]"

if (-not (Test-Path $vswhere)) {
    Write-Error "vswhere.exe not found"
    exit 1
}

if ("$vsversion" -eq "latest") {
    $vspath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
}
else {
    $vspath = & $vswhere -version $vsversion -products * -requires Microsoft.Component.MSBuild -property installationPath
}
if ($LASTEXITCODE) {
    Write-Error "vswhere failed: $LASTEXITCODE"
    if ($vspath) {
        $vspath | Where-Object { $_ -match "^Error" } | ForEach-Object { Write-Error $_ }
    }
    exit 1
}
# Write-Host "::notice::vspath = [$vspath]"

if (-not $vspath) {
    Write-Error "Visual Studio not found"
    exit 1
}

$vcvars = Join-Path $vspath "VC\Auxiliary\Build\vcvarsall.bat"
# Write-Host "::notice::vcvars = [$vcvars]"

if (-not (Test-Path $vcvars)) {
    Write-Error "vcvarsall.bat not found"
    exit 1
}

Write-Host "Found with vswhere: $vcvars"

# Run vcvarsall.bat and capture environment variables
$outBefore = New-TemporaryFile
$outVcvars = New-TemporaryFile
$outAfter  = New-TemporaryFile

$optVcvars = ""
if ($Sdk) {
    $optVcvars += " $Sdk"
}
if ($ToolSet) {
    $optVcvars += " -vcvars_ver=$ToolSet"
}

cmd /c "SET >`"$outBefore`" && `"$vcvars`" $arch $optVcvars >`"$outVcvars`" && SET >`"$outAfter`""
if ($LASTEXITCODE) {
    Write-Error "vcvarsall.bat failed: $LASTEXITCODE"
    exit 1
}

# Check vcvarsall.bat error
$errVcvars = Select-String -Path $outVcvars -Pattern "^\[ERROR" | Select-Object -ExpandProperty Line
if ($errVcvars) {
    Write-Error "vcvarsall.bat failed"
    foreach ($line in $errVcvars) {
        Write-Error $line
    }
    exit 1
}

# Save environment variables before running vcvarsall.bat
$before = @{}
Get-Content $outBefore | ForEach-Object {
    if ($_ -match "^(.*?)=(.*)$") {
        $before[$matches[1]] = $matches[2]
    }
}

Write-Host "::group::Environment variables"

# Set the added or modified environment variables
Get-Content $outAfter | ForEach-Object {
    if ($_ -match "^(.*?)=(.*)$") {
        $key = $matches[1]
        $val = $matches[2]
        if (-not $before.ContainsKey($key) -or $before[$key] -ne $val) {
            Write-Host "Setting $key"
            "$key=$val" >> $env:GITHUB_ENV
        }
    }
}

Write-Host "::endgroup::"

Write-Host "Configured Developer Command Prompt"
