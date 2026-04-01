param(
    [switch]$SyncWeb,
    [switch]$BuildDesktop,
    [switch]$AndroidPrep,
    [switch]$GitCommit,
    [switch]$GitPush,
    [string]$CommitMessage
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$FrontendRoot = Join-Path $RepoRoot "src"
$AppResourceRoot = "d:\Software\Nuztrack\Nuztrack-win32-x64\resources\app"

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
    & $Action
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

function Start-InteractiveMode {
    Write-Section "Nuztrack Release CLI"

    $script:SyncWeb = Read-Choice "Sync Web UI changes from Electron workspace to Tauri repository?" $true
    $script:BuildDesktop = Read-Choice "Build the Tauri desktop app?" $true
    $script:AndroidPrep = Read-Choice "Prep the Android folder natively? (Does NOT execute build, just prepares code!)" $true
    
    $script:GitCommit = Read-Choice "Create a git commit for this release?" $false
    if ($script:GitCommit) {
        $defaultCommit = "Update via script"
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

$explicitActions = $SyncWeb -or $BuildDesktop -or $AndroidPrep -or $GitCommit -or $GitPush
if (-not $explicitActions) {
    Start-InteractiveMode
}

if (-not $CommitMessage) {
    $CommitMessage = "Update via script"
}

Write-Section "Release Summary"
Write-Host "Sync Web      : $SyncWeb"
Write-Host "Build Desktop : $BuildDesktop"
Write-Host "Android Prep  : $AndroidPrep"
Write-Host "Git Commit    : $GitCommit"
Write-Host "Git Push      : $GitPush"

if ($SyncWeb) {
    Invoke-Step "Syncing Javascript/Web resources" {
        # Using xcopy in PowerShell
        & xcopy "$AppResourceRoot\*.js" "$FrontendRoot\" /Y
        & xcopy "$AppResourceRoot\*.css" "$FrontendRoot\" /Y
        & xcopy "$AppResourceRoot\*.html" "$FrontendRoot\" /Y
        Write-Host "   Overwritten Tauri src directory with Web source." -ForegroundColor DarkGreen
    }
}

if ($BuildDesktop) {
    Invoke-Step "Building Tauri Windows standalone" {
        Invoke-External "npm.cmd" @("run", "build") $RepoRoot
    }
}

if ($AndroidPrep) {
    Invoke-Step "Prepping Android Development Folder" {
        # The frontend code is already synced. Now Tauri relies on Gradle/Android Studio.
        Write-Host "   Frontend Android code successfully staged!" -ForegroundColor Green
        Write-Host "   ACTION REQUIRED: Navigate into 'src-tauri\gen\android' via your Android Studio IDE or execute ./gradlew directly there to deploy to connected devices." -ForegroundColor DarkYellow
    }
}

if ($GitCommit) {
    Invoke-Step "Adding and Committing into GitHub history" {
        Invoke-External "git.exe" @("add", ".") $RepoRoot
        Invoke-External "git.exe" @("commit", "-m", $CommitMessage) $RepoRoot
    }
}

if ($GitPush) {
    Invoke-Step "Pushing commit into Mainline branch" {
        Invoke-External "git.exe" @("push") $RepoRoot
    }
}

Write-Host ""
Write-Host "Release flow accurately finalized." -ForegroundColor Green
