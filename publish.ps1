param(
    [string]$Version,
    [switch]$FailFast,
    [switch]$InstallDeps,
    [switch]$BuildDesktop,
    [switch]$GitCommit,
    [switch]$GitPush,
    [string]$CommitMessage
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$SafeRepoRoot = $RepoRoot.Replace("\\", "/")

$script:StepErrors = @()

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

function Set-ProjectVersion {
    param(
        [string]$NewVersion
    )

    if ($NewVersion -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "Version must be in the form x.y.z. Got: '$NewVersion'"
    }

    Update-JsonVersion (Join-Path $RepoRoot "package.json") $NewVersion
    Update-JsonVersion (Join-Path $RepoRoot "package-lock.json") $NewVersion
    Update-JsonVersion (Join-Path $RepoRoot "src-tauri\tauri.conf.json") $NewVersion
    Update-CargoTomlPackageVersion (Join-Path $RepoRoot "src-tauri\Cargo.toml") $NewVersion

    Write-Host "Updated version to $NewVersion" -ForegroundColor Green
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

function Get-DesktopArtifacts {
    $bundleRoot = Join-Path $RepoRoot "src-tauri\target\release\bundle"
    if (-not (Test-Path -LiteralPath $bundleRoot)) {
        return @()
    }

    return Get-ChildItem -Path $bundleRoot -Recurse -File |
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
        $GitCommit -or
        $GitPush

    if (-not $explicitActions) {
        Start-InteractiveMode
    }

    if (-not $CommitMessage) {
        $CommitMessage = "Release via publish.ps1"
    }

    Write-Section "Release Summary"
    Write-Host "Version        : $Version"
    Write-Host "Install Deps   : $InstallDeps"
    Write-Host "Build Desktop  : $BuildDesktop"
    Write-Host "Git Commit     : $GitCommit"
    Write-Host "Git Push       : $GitPush"
    Write-Host "Fail Fast      : $FailFast"

    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        Invoke-Step "Updating project version" {
            Set-ProjectVersion $Version
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

    if ($GitCommit) {
        Invoke-Step "Creating git commit" {
            Invoke-External "git.exe" @("-c", "safe.directory=$SafeRepoRoot", "add", ".")
            Invoke-External "git.exe" @("-c", "safe.directory=$SafeRepoRoot", "commit", "-m", $CommitMessage)
        }
    }

    if ($GitPush) {
        Invoke-Step "Pushing git changes" {
            Invoke-External "git.exe" @("-c", "safe.directory=$SafeRepoRoot", "push", "origin", "main")
        }
    }

    Show-Artifacts "Desktop Artifacts" (Get-DesktopArtifacts)

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
