param(
    [string]$Version,
    [int]$AndroidVersionCode,
    [switch]$FailFast,
    [switch]$InstallDeps,
    [switch]$BuildDesktop,
    [switch]$BuildAndroid,
    [ValidateSet("debug", "release")]
    [string]$AndroidProfile = "debug",
    [switch]$AndroidApk,
    [switch]$AndroidAab,
    [switch]$GitCommit,
    [switch]$GitPush,
    [string]$CommitMessage
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$SafeRepoRoot = $RepoRoot.Replace("\", "/")
$AndroidSdkRoot = "D:\Software\Android SDK"
$DefaultJavaHome = Join-Path $AndroidSdkRoot "jbr"
$DefaultNdkHome = Join-Path $AndroidSdkRoot "ndk\27.2.12479018"

$script:StepErrors = @()

function Get-ComputedAndroidVersionCode {
    param([string]$SemVer)

    if ($SemVer -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "Version must be in the form x.y.z for Android versionCode computation. Got: '$SemVer'"
    }

    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]

    return ($major * 1000000) + ($minor * 1000) + $patch
}

function Update-JsonVersion {
    param(
        [string]$FilePath,
        [string]$NewVersion
    )

    $content = Get-Content -LiteralPath $FilePath -Raw
    $updated = [regex]::Replace(
        $content,
        '(?m)^\s*"version"\s*:\s*"[^\"]+"\s*,?\s*$',
        { param($m) $m.Value -replace '"version"\s*:\s*"[^\"]+"', ('"version": "' + $NewVersion + '"') },
        1
    )

    if ($updated -eq $content) {
        throw "Failed to update version in JSON file: $FilePath"
    }

    Set-Content -LiteralPath $FilePath -Value $updated -NoNewline
}

function Update-CargoTomlPackageVersion {
    param(
        [string]$FilePath,
        [string]$NewVersion
    )

    $lines = Get-Content -LiteralPath $FilePath
    $inPackage = $false
    $changed = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line -match '^\s*\[package\]\s*$') {
            $inPackage = $true
            continue
        }

        if ($inPackage -and $line -match '^\s*\[.+\]\s*$') {
            # Leaving [package] section without finding version key.
            break
        }

        if ($inPackage -and $line -match '^\s*version\s*=\s*".*"\s*$') {
            $lines[$i] = 'version = "' + $NewVersion + '"'
            $changed = $true
            break
        }
    }

    if (-not $changed) {
        throw "Failed to update [package].version in: $FilePath"
    }

    Set-Content -LiteralPath $FilePath -Value $lines
}

function Update-TauriAndroidPropertiesVersion {
    param(
        [string]$FilePath,
        [string]$NewVersion,
        [int]$NewVersionCode
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        return
    }

    $content = Get-Content -LiteralPath $FilePath -Raw
    $content = [regex]::Replace($content, '(?m)^tauri\.android\.versionName=.*$', ('tauri.android.versionName=' + $NewVersion))
    $content = [regex]::Replace($content, '(?m)^tauri\.android\.versionCode=.*$', ('tauri.android.versionCode=' + $NewVersionCode))
    Set-Content -LiteralPath $FilePath -Value $content -NoNewline
}

function Set-ProjectVersion {
    param(
        [string]$NewVersion,
        [int]$NewAndroidVersionCode
    )

    if ($NewVersion -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "Version must be in the form x.y.z. Got: '$NewVersion'"
    }

    $resolvedAndroidCode = $NewAndroidVersionCode
    if ($resolvedAndroidCode -le 0) {
        $resolvedAndroidCode = Get-ComputedAndroidVersionCode $NewVersion
    }

    Update-JsonVersion (Join-Path $RepoRoot "package.json") $NewVersion
    Update-JsonVersion (Join-Path $RepoRoot "package-lock.json") $NewVersion
    Update-JsonVersion (Join-Path $RepoRoot "src-tauri\tauri.conf.json") $NewVersion
    Update-CargoTomlPackageVersion (Join-Path $RepoRoot "src-tauri\Cargo.toml") $NewVersion
    Update-TauriAndroidPropertiesVersion (Join-Path $RepoRoot "src-tauri\gen\android\app\tauri.properties") $NewVersion $resolvedAndroidCode

    Write-Host "Updated version to $NewVersion (Android versionCode: $resolvedAndroidCode)" -ForegroundColor Green
}

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message ==" -ForegroundColor Cyan
}

function Invoke-Step {
    param(
        [string]$Label,
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "-> $Label" -ForegroundColor Yellow
    try {
        & $Action
    } catch {
        $script:StepErrors += $_
        Write-Host ""
        Write-Host "!! Step failed: $Label" -ForegroundColor Red
        Write-Host ("   " + $_.Exception.Message) -ForegroundColor Red
        if ($_.ScriptStackTrace) {
            Write-Host "   Stack:" -ForegroundColor DarkRed
            $_.ScriptStackTrace.Trim().Split("`n") | ForEach-Object {
                Write-Host ("   " + $_.Trim()) -ForegroundColor DarkRed
            }
        }
        if ($FailFast) {
            throw
        }
    }
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory = $RepoRoot
    )

    Push-Location $WorkingDirectory
    try {
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($ArgumentList -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Read-Choice {
    param(
        [string]$Prompt,
        [bool]$DefaultValue = $false
    )

    $suffix = if ($DefaultValue) { "[Y/n]" } else { "[y/N]" }
    $answer = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $DefaultValue
    }

    return $answer.Trim().ToLowerInvariant() -in @("y", "yes")
}

function Read-Option {
    param(
        [string]$Prompt,
        [string]$DefaultValue,
        [string[]]$AllowedValues
    )

    $displayValues = ($AllowedValues -join "/")
    $answer = Read-Host "$Prompt [$displayValues] (default: $DefaultValue)"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $DefaultValue
    }

    $normalized = $answer.Trim().ToLowerInvariant()
    if ($AllowedValues -contains $normalized) {
        return $normalized
    }

    throw "Invalid choice '$answer'. Allowed values: $displayValues"
}

function Ensure-PathExists {
    param(
        [string]$PathValue,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $PathValue)) {
        throw "$Label not found: $PathValue"
    }
}

function Ensure-GitSafe {
    Invoke-External "git.exe" @("-c", "safe.directory=$SafeRepoRoot", "status", "--short")
}

function Ensure-AndroidEnvironment {
    if (-not $env:JAVA_HOME) {
        $env:JAVA_HOME = $DefaultJavaHome
    }
    if (-not $env:ANDROID_HOME) {
        $env:ANDROID_HOME = $AndroidSdkRoot
    }
    if (-not $env:NDK_HOME) {
        $env:NDK_HOME = $DefaultNdkHome
    }

    Ensure-PathExists $env:JAVA_HOME "JAVA_HOME"
    Ensure-PathExists $env:ANDROID_HOME "ANDROID_HOME"
    Ensure-PathExists $env:NDK_HOME "NDK_HOME"
    Ensure-PathExists (Join-Path $env:ANDROID_HOME "platform-tools") "Android platform-tools"
    Ensure-PathExists (Join-Path $RepoRoot "src-tauri\gen\android\gradlew.bat") "Generated Android project"
}

function Get-DesktopArtifacts {
    $bundleRoot = Join-Path $RepoRoot "src-tauri\target\release\bundle"
    if (-not (Test-Path -LiteralPath $bundleRoot)) {
        return @()
    }

    return Get-ChildItem -Path $bundleRoot -Recurse -File |
        Select-Object FullName, Length, LastWriteTime
}

function Get-AndroidArtifacts {
    $outputsRoot = Join-Path $RepoRoot "src-tauri\gen\android\app\build\outputs"
    if (-not (Test-Path -LiteralPath $outputsRoot)) {
        return @()
    }

    return Get-ChildItem -Path $outputsRoot -Recurse -File |
        Where-Object { $_.Extension -in @(".apk", ".aab") } |
        Select-Object FullName, Length, LastWriteTime
}

function Show-Artifacts {
    param(
        [string]$Title,
        [object[]]$Artifacts
    )

    Write-Section $Title
    if (-not $Artifacts -or $Artifacts.Count -eq 0) {
        Write-Host "No artifacts found." -ForegroundColor DarkYellow
        return
    }

    $Artifacts | Sort-Object FullName | ForEach-Object {
        $sizeMb = [Math]::Round($_.Length / 1MB, 2)
        Write-Host "$($_.FullName) ($sizeMb MB)"
    }
}

function Start-InteractiveMode {
    Write-Section "Nuztrack Release CLI"

    $script:Version = Read-Host "Version to set (x.y.z) [leave blank to keep current]"
    if ([string]::IsNullOrWhiteSpace($script:Version)) {
        $script:Version = $null
    }

    $script:InstallDeps = Read-Choice "Run npm install first?" $false
    $script:BuildDesktop = Read-Choice "Build the Tauri desktop release?" $true
    $script:BuildAndroid = Read-Choice "Build the Tauri Android app?" $true

    if ($script:BuildAndroid) {
        $script:AndroidProfile = Read-Option "Android build profile" "debug" @("debug", "release")
        $script:AndroidApk = Read-Choice "Generate APK?" $true
        $script:AndroidAab = Read-Choice "Generate AAB?" $false
    }

    $script:GitCommit = Read-Choice "Create a git commit for this release?" $false
    if ($script:GitCommit) {
        $defaultCommit = "Release via publish.ps1"
        $enteredCommit = Read-Host "Commit message [$defaultCommit]"
        if ([string]::IsNullOrWhiteSpace($enteredCommit)) {
            $script:CommitMessage = $defaultCommit
        } else {
            $script:CommitMessage = $enteredCommit
        }
        $script:GitPush = Read-Choice "Push the commit to GitHub?" $false
    } else {
        $script:GitPush = $false
    }
}

try {
    $explicitActions =
        (-not [string]::IsNullOrWhiteSpace($Version)) -or
        $InstallDeps -or
        $BuildDesktop -or
        $BuildAndroid -or
        $GitCommit -or
        $GitPush

    if (-not $explicitActions) {
        Start-InteractiveMode
    }

    if (-not $BuildAndroid) {
        $AndroidApk = $false
        $AndroidAab = $false
    }

    if ($BuildAndroid -and -not ($AndroidApk -or $AndroidAab)) {
        $AndroidApk = $true
    }

    if (-not $CommitMessage) {
        $CommitMessage = "Release via publish.ps1"
    }

    Write-Section "Release Summary"
    Write-Host "Version        : $Version"
    Write-Host "Install Deps   : $InstallDeps"
    Write-Host "Build Desktop  : $BuildDesktop"
    Write-Host "Build Android  : $BuildAndroid"
    Write-Host "Android Profile: $AndroidProfile"
    Write-Host "Android APK    : $AndroidApk"
    Write-Host "Android AAB    : $AndroidAab"
    Write-Host "Git Commit     : $GitCommit"
    Write-Host "Git Push       : $GitPush"
    Write-Host "Fail Fast      : $FailFast"

    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        Invoke-Step "Updating project version" {
            Set-ProjectVersion $Version $AndroidVersionCode
        }
    }

    if ($InstallDeps) {
        Invoke-Step "Installing npm dependencies" {
            Invoke-External "npm.cmd" @("install")
        }
    }

    if ($BuildDesktop) {
        Invoke-Step "Building Windows desktop release" {
            Invoke-External "npm.cmd" @("run", "build")
        }
    }

    if ($BuildAndroid) {
        Invoke-Step "Preparing Android environment" {
            Ensure-AndroidEnvironment
            Write-Host "JAVA_HOME    : $env:JAVA_HOME"
            Write-Host "ANDROID_HOME : $env:ANDROID_HOME"
            Write-Host "NDK_HOME     : $env:NDK_HOME"
        }

        Invoke-Step "Building Android artifacts" {
            $androidArgs = @("tauri", "android", "build")

            if ($AndroidProfile -eq "debug") {
                $androidArgs += "--debug"
            }

            if ($AndroidApk) {
                $androidArgs += "--apk"
            }

            if ($AndroidAab) {
                $androidArgs += "--aab"
            }

            $androidArgs += "--ci"

            Invoke-External "npx.cmd" $androidArgs
        }
    }

    if ($GitCommit) {
        Invoke-Step "Creating git commit" {
            Ensure-GitSafe
            Invoke-External "git.exe" @("-c", "safe.directory=$SafeRepoRoot", "add", ".")
            Invoke-External "git.exe" @("-c", "safe.directory=$SafeRepoRoot", "commit", "-m", $CommitMessage)
        }
    }

    if ($GitPush) {
        Invoke-Step "Pushing git changes" {
            Ensure-GitSafe
            Invoke-External "git.exe" @("-c", "safe.directory=$SafeRepoRoot", "push", "origin", "main")
        }
    }

    Show-Artifacts "Desktop Artifacts" (Get-DesktopArtifacts)
    Show-Artifacts "Android Artifacts" (Get-AndroidArtifacts)

    if ($script:StepErrors.Count -gt 0) {
        Write-Section "Errors"
        Write-Host ("Completed with " + $script:StepErrors.Count + " error(s).") -ForegroundColor Red
        $script:StepErrors | ForEach-Object {
            Write-Host ("- " + $_.Exception.Message) -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "Release flow finished." -ForegroundColor Green
} catch {
    # Catch any non-step failures, print them, and avoid terminating the host.
    Write-Host ""
    Write-Host "!! Script failed unexpectedly" -ForegroundColor Red
    Write-Host ("   " + $_.Exception.Message) -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        Write-Host "   Stack:" -ForegroundColor DarkRed
        $_.ScriptStackTrace.Trim().Split("`n") | ForEach-Object {
            Write-Host ("   " + $_.Trim()) -ForegroundColor DarkRed
        }
    }
}
