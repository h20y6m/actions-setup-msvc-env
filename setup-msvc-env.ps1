# Setup MSVC Environment Variables

param(
    [string]$Arch = "",
    [string]$Sdk = "",
    [string]$Toolset = "",
    [string]$VsVersion = ""
)

if (-not $Arch) {
    if ($env:RUNNER_ARCH) {
        $Arch = $env:RUNNER_ARCH.ToLower()
    }
    else {
        $Arch = $env:PROCESSOR_ARCHITECTURE.ToLower()
    }
}

switch ($VsVersion) {
    "2017" { $VsVersion = "[15.0,16.0)" }
    "2019" { $VsVersion = "[16.0,17.0)" }
    "2022" { $VsVersion = "[17.0,18.0)" }
    "2026" { $VsVersion = "[18.0,19.0)" }
}
if ($VsVersion -match "^(\d+)(\.\d)?$") {
    $max = ([int]$matches[1] + 1)
    $VsVersion = "[$VsVersion,$max)"
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

if (-not (Test-Path $vswhere)) {
    Write-Host "::error::vswhere.exe not found"
    exit 1
}

if ($VsVersion) {
    $vspath = & $vswhere -version $VsVersion -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
}
else {
    $vspath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
}
if ($LASTEXITCODE) {
    Write-Host "::error::vswhere failed: $LASTEXITCODE"
    if ($vspath) {
        Write-Host "::group::vswhere error messages"
        $vspath | Where-Object { $_ -match "^Error" } | ForEach-Object { Write-Host $_ }
        Write-Host "::endgroup::"
    }
    exit 1
}

if (-not $vspath) {
    Write-Host "::error::Visual Studio not found"
    exit 1
}

$vcvars = Join-Path $vspath "VC\Auxiliary\Build\vcvarsall.bat"

if (-not (Test-Path $vcvars)) {
    Write-Host "::error::vcvarsall.bat not found"
    exit 1
}

Write-Host "Found with vswhere: $vcvars"

# vcvarsall.bat options
$optVcvars = ""
if ($Sdk) {
    $optVcvars += " $Sdk"
}
if ($Toolset) {
    switch ($Toolset.ToLower()) {
        "vs2017" { $Toolset = "v141" }
        "vs2019" { $Toolset = "v142" }
        "vs2022" { $Toolset = "v143" }
        "vs2026" { $Toolset = "v145" }
    }
    if ($Toolset.StartsWith("v")) {
        $defaultTxtPath = Join-Path $vspath "VC\Auxiliary\Build\Microsoft.VCToolsVersion.$Toolset.default.txt"
        if (Test-Path $defaultTxtPath) {
            $Toolset = Get-Content -Path $defaultTxtPath -TotalCount 1
        }
        else {
            # VS2026 hasn't Microsoft.VCToolsVersion.v145.default.txt
            # Scan the v145 directory to find the latest version.
            $vPath = Join-Path $vspath "VC\Auxiliary\Build\$Toolset"
            if (Test-Path $vPath) {
                $toolsVersions = Get-ChildItem -Path $vPath -File -Filter "Microsoft.VCToolsVersion.VC.*.txt" | ForEach-Object {
                    Get-Content -Path $_ -TotalCount 1
                }
                $latest = $null
                foreach ($toolsVersion in $toolsVersions) {
                    try {
                        $version = [version]$toolsVersion
                        if (!$latest -or $latest -lt $version) {
                            $latest = $version
                            $Toolset = $toolsVersion
                        }
                    }
                    catch {}
                }
            }
        }
    }
    $optVcvars += " -vcvars_ver=$Toolset"
}

# Run vcvarsall.bat and capture environment variables
$tmpBefore = New-TemporaryFile
$tmpAfter = New-TemporaryFile
try {
    $output = & cmd /c "SET >`"$tmpBefore`" && `"$vcvars`" $Arch $optVcvars && SET >`"$tmpAfter`""
    $exitcode = $LASTEXITCODE
    $outBefore = Get-Content -Path $tmpBefore
    $outAfter = Get-Content -Path $tmpAfter
}
finally {
    if (Test-Path $tmpBefore) { Remove-Item -Path $tmpBefore -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tmpAfter) { Remove-Item -Path $tmpAfter -Force -ErrorAction SilentlyContinue }
}

# Check vcvarsall.bat error
if ($exitcode) {
    Write-Host "::error::vcvarsall.bat failed: $exitcode"
    exit 1
}
$errVcvars = $output | Where-Object { $_ -match "^\[ERROR" }
if ($errVcvars) {
    Write-Host "::error::vcvarsall.bat failed"
    Write-Host "::group::vcvarsall.bat error messages"
    foreach ($line in $errVcvars) {
        Write-Host "$line"
    }
    Write-Host "::endgroup::"
    exit 1
}

# Save environment variables before running vcvarsall.bat
$before = @{}
foreach ($line in $outBefore) {
    if ($line -match "^([^=]+?)=(.*)$") {
        $before[$matches[1]] = $matches[2]
    }
}

# Set the added or modified environment variables
Write-Host "::group::Environment variables"
foreach ($line in $outAfter) {
    if ($line -match "^([^=]+?)=(.*)$") {
        $name = $matches[1]
        $value = $matches[2]
        if (-not $before.ContainsKey($name) -or $before[$name] -ne $value) {
            Write-Host "Setting $name"
            Set-Item -Path "env:\$name" -Value $value
            if ($env:GITHUB_ENV) {
                "$name=$value" >> $env:GITHUB_ENV
            }
        }
    }
}
Write-Host "::endgroup::"

Write-Host "Configured Developer Command Prompt"
