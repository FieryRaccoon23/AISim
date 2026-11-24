param(
    # The shared local-model folder (Strata, Headroom, claude-local.cmd). Same as run-tasks.ps1.
    [string]$LocalLLMDir = "D:\LocalLLM",
    # The agent is killed after this many minutes.
    [int]$TimeoutMinutes = 60,
    [string]$SourceDir = "src",
    [string]$VendorDir = "vendor",
    # Only read for package names and versions.
    [string]$RequirementsFile = "requirements.txt",
    # Leave the local model server running when the script finishes, even if this script started it.
    [switch]$KeepServerRunning
)

# Run from the project root (D:\AISim\AISim). This script's only job is to (re)create CODEBASE_MAP.md.
# It never runs git, never installs anything and never runs any Python.
# If anything other than CODEBASE_MAP.md changes, or the result looks broken, the old map is restored.
if ($PSScriptRoot) { Set-Location -LiteralPath $PSScriptRoot }
$ErrorActionPreference = "Continue"
$startScript = Join-Path $LocalLLMDir "start.ps1"
$stopScript = Join-Path $LocalLLMDir "stop.ps1"
$claudeLocal = Join-Path $LocalLLMDir "claude-local.cmd"
$mapFile = "CODEBASE_MAP.md"
$backupFile = "CODEBASE_MAP.md.bak"

# Same MCP settings as run-tasks.ps1: no extra servers, no book search. Old values are restored at the end.
$oldStrictMcp = $env:CLAUDE_LOCAL_STRICT_MCP
$oldNoRag = $env:CLAUDE_LOCAL_NO_RAG
$env:CLAUDE_LOCAL_STRICT_MCP = "1"
$env:CLAUDE_LOCAL_NO_RAG = "1"

# ---------------------------------------------------------------- helpers

function Get-Rel([string]$fullPath) {
    $root = (Get-Location).Path.TrimEnd('\') + '\'
    return $fullPath.Replace($root, '')
}

# Path -> "size|last write time" for the files the agent could touch (root files, src, vendor), ignoring caches
# and the map itself. Used to prove the agent touched nothing but CODEBASE_MAP.md. The venv is never scanned.
function Get-ProjectSnapshot {
    $map = @{}
    $items = @()
    $items += Get-ChildItem -File -Force -ErrorAction SilentlyContinue
    foreach ($d in @($SourceDir, $VendorDir)) {
        if (Test-Path $d) { $items += Get-ChildItem -Path $d -Recurse -File -Force -ErrorAction SilentlyContinue }
    }
    $items |
        Where-Object {
            $_.FullName -notmatch '[\\/](__pycache__|\.pytest_cache|\.ruff_cache|\.mypy_cache)[\\/]' -and
            $_.Extension -ne '.pyc' -and
            $_.Name -notin @('CODEBASE_MAP.md', 'CODEBASE_MAP.md.bak')
        } |
        ForEach-Object { $map[$_.FullName] = "$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" }
    return $map
}

function Get-ChangedFiles($before, $after) {
    $changed = @()
    foreach ($path in $after.Keys) {
        if (-not $before.ContainsKey($path) -or $before[$path] -ne $after[$path]) { $changed += $path }
    }
    foreach ($path in $before.Keys) {
        if (-not $after.ContainsKey($path)) { $changed += "$path (deleted)" }
    }
    $root = (Get-Location).Path.TrimEnd('\') + '\'
    return @($changed | ForEach-Object { $_.Replace($root, '') } | Sort-Object)
}

# The .py files that get described: all of src, except caches, tests and tiny (empty) __init__.py files.
function Get-MapFiles {
    return @(Get-ChildItem -Path $SourceDir -Recurse -File -Filter *.py -ErrorAction SilentlyContinue |
        Where-Object {
            (Get-Rel $_.FullName) -notmatch '(^|[\\/])(__pycache__|tests)[\\/]' -and
            -not ($_.Name -eq '__init__.py' -and $_.Length -lt 200)
        } | Sort-Object FullName)
}

# Runs claude-local.cmd -p with the prompt on stdin; kills the whole process tree on timeout.
function Invoke-Agent([string]$prompt) {
    $inFile = [System.IO.Path]::GetTempFileName()
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $inFile -Value $prompt -Encoding UTF8
        $proc = Start-Process -FilePath $claudeLocal -ArgumentList "-p" -NoNewWindow -PassThru `
            -RedirectStandardInput $inFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $finished = $proc.WaitForExit($TimeoutMinutes * 60 * 1000)
        if (-not $finished) {
            & taskkill /PID $proc.Id /T /F | Out-Null
            return @{ TimedOut = $true; Output = "" }
        }
        $out = (Get-Content $outFile -Raw -Encoding UTF8) + (Get-Content $errFile -Raw -Encoding UTF8)
        return @{ TimedOut = $false; Output = $out }
    }
    finally {
        Remove-Item $inFile, $outFile, $errFile -ErrorAction SilentlyContinue
    }
}

function Restore-OldMap([bool]$hadOldMap) {
    if ($hadOldMap -and (Test-Path $backupFile)) {
        Copy-Item $backupFile $mapFile -Force
        Write-Host "The previous $mapFile was restored." -ForegroundColor Yellow
    }
    elseif (Test-Path $mapFile) {
        Remove-Item $mapFile -Force
    }
}

# Keep Windows from sleeping while this script runs.
Add-Type -Namespace LocalLLM -Name Power -MemberDefinition `
    '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
[LocalLLM.Power]::SetThreadExecutionState([uint32]2147483649) | Out-Null   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED

# ---------------------------------------------------------------- main

$weStartedServer = $false
try {
    # --- Preflight ---
    if (-not (Test-Path $SourceDir)) { Write-Host "$SourceDir not found. Run this from the project root."; exit 1 }
    if (-not (Test-Path $RequirementsFile)) { Write-Host "$RequirementsFile not found. Run this from the project root, or pass -RequirementsFile."; exit 1 }
    if (-not (Test-Path $claudeLocal)) { Write-Host "$claudeLocal not found. Run $LocalLLMDir\setup.ps1 first."; exit 1 }
    if (-not (Get-Command claude.exe, claude.cmd -ErrorAction SilentlyContinue)) { Write-Host "claude (Claude Code CLI) not found on PATH."; exit 1 }

    $csFiles = Get-MapFiles
    if ($csFiles.Count -eq 0) { Write-Host "No .py files found under $SourceDir. Nothing to map."; exit 1 }

    # --- Make sure the local model server is up ---
    & $startScript -CheckOnly | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Starting the local model server..." -ForegroundColor Cyan
        & $startScript
        if ($LASTEXITCODE -ne 0) { Write-Host "The local model server could not be started." -ForegroundColor Red; exit 1 }
        $weStartedServer = $true
    }

    # --- Back up the existing map, then regenerate it ---
    $hadOldMap = Test-Path $mapFile
    if ($hadOldMap) {
        Copy-Item $mapFile $backupFile -Force
        Write-Host "Backed up the current map to $backupFile" -ForegroundColor DarkGray
    }

    $before = Get-ProjectSnapshot
    Write-Host "Updating $mapFile from the current code... ($(Get-Date -Format HH:mm))" -ForegroundColor Cyan

    $existingNote = if ($hadOldMap) {
        "An older CODEBASE_MAP.md already exists. The code is the truth: re-read ALL of it and rewrite the file so it matches the code as it is now. Keep the wording of lines that are still correct, drop entries for classes and functions that no longer exist, and add entries for new ones."
    }
    else {
        "No CODEBASE_MAP.md exists yet. Create it."
    }

    # Exact file list: the agent is told to read these and nothing else.
    $fileList = ($csFiles | ForEach-Object { "- " + (Get-Rel $_.FullName) }) -join "`n"

    $prompt = @"
Your ONLY job is to write CODEBASE_MAP.md, describing the Python code. Do not change any other file. Do not run any git command. Do not run any command at all (no python, no pip).

$existingNote

Read ONLY these files:
$RequirementsFile (package names and versions only)
$fileList

Do NOT open, list or read anything else: nothing in $VendorDir, no virtual environment, no tests folder, no data files, no __pycache__. Describe code only.

Format:
1. One line with the Python version (3.12) and the packages from $RequirementsFile.
2. A short 'Boot flow' tree: entry points (files with an if __name__ == "__main__" guard), what they call, and how the folders (modules) depend on each other through imports. Base it on the code only.
3. 'Folders and classes': one heading per folder under $SourceDir (import name = folder name; files directly in $SourceDir get their own heading), then one short line per class and per public top-level function: base class, purpose, key public methods, which file.

Keep it concise. No code listings. Every class and public top-level function in the files above must appear exactly once.
"@

    $r = Invoke-Agent $prompt
    Write-Host $r.Output
    if ($r.TimedOut) {
        Write-Host "The agent timed out after $TimeoutMinutes minutes." -ForegroundColor Red
        Restore-OldMap $hadOldMap
        exit 2
    }

    # --- Check the result ---
    $problem = $null
    $changedElsewhere = Get-ChangedFiles $before (Get-ProjectSnapshot)
    if ($changedElsewhere.Count -gt 0) {
        $problem = "The agent changed files other than ${mapFile}:`n  " + ($changedElsewhere -join "`n  ")
    }
    elseif (-not (Test-Path $mapFile)) {
        $problem = "$mapFile was not created."
    }
    elseif ((Get-Item $mapFile).Length -lt 300) {
        $problem = "$mapFile is almost empty."
    }
    else {
        # Every public class and top-level function should show up in the map. A file with none must show up by name.
        $mapText = Get-Content $mapFile -Raw
        $expected = @()
        foreach ($f in (Get-MapFiles)) {
            $code = Get-Content $f.FullName -Raw -Encoding UTF8
            if (-not $code) { $code = "" }
            $found = @([regex]::Matches($code, '(?m)^(?:async\s+def|def|class)\s+([A-Za-z]\w*)') | ForEach-Object { $_.Groups[1].Value })
            if ($found.Count -gt 0) { $expected += $found } else { $expected += $f.BaseName }
        }
        $missing = @($expected | Sort-Object -Unique | Where-Object { $mapText -notmatch [regex]::Escape($_) })
        if ($missing.Count -gt 0) {
            Write-Host "Warning: these names are not mentioned in the map: $($missing -join ', ')" -ForegroundColor Yellow
            Write-Host "Run the script again, or add them by hand." -ForegroundColor Yellow
        }
    }

    if ($problem) {
        Write-Host $problem -ForegroundColor Red
        Restore-OldMap $hadOldMap
        exit 3
    }

    Write-Host "`n$mapFile updated. Nothing else was changed and nothing was committed." -ForegroundColor Green
    if (Test-Path $backupFile) { Remove-Item $backupFile -Force }
}
finally {
    [LocalLLM.Power]::SetThreadExecutionState([uint32]2147483648) | Out-Null   # allow sleep again
    $env:CLAUDE_LOCAL_STRICT_MCP = $oldStrictMcp
    $env:CLAUDE_LOCAL_NO_RAG = $oldNoRag

    # Stop the server only if this script started it, also after a failure.
    if ($weStartedServer -and -not $KeepServerRunning -and (Test-Path $stopScript)) {
        Write-Host "Stopping the local model server..." -ForegroundColor Cyan
        & $stopScript
    }
}
