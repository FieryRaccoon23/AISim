param(
    [int]$MaxRetries = 3,
    [string]$TasksFile = "TASKS.md",
    # Tasks build on each other, so by default the runner stops at the first failed task.
    [switch]$ContinueOnFailure,
    # The shared local-model folder (Strata, Headroom, claude-local.cmd).
    [string]$LocalLLMDir = "D:\LocalLLM",
    # One agent attempt is killed after this many minutes. Local models are much slower than the cloud.
    [int]$AttemptTimeoutMinutes = 60,
    # The virtual environment folder. Looked for in the project root first, then one folder above it.
    [string]$VenvName = "venv_AISim",
    [string]$SourceDir = "src",
    [string]$VendorDir = "vendor",
    [string]$RequirementsFile = "requirements.txt",
    # Skip ruff even if it is installed.
    [switch]$SkipLint,
    # Also run mypy after each task (only if mypy is installed in the venv). Off by default: it can be noisy.
    [switch]$UseMypy,
    # Leave the local model server running when the script finishes. By default it is stopped at the end,
    # also after a failure.
    [switch]$KeepServerRunning,
    # Task runs load no MCP servers: not your user/project ones, and not the book search (D:\RAG).
    # Tasks are exact specs, and every tool description and search costs context and minutes on the
    # local model. -UseBookSearch adds the book search back (still nothing else).
    [switch]$UseBookSearch
)

# Run from the project root (D:\AISim\AISim, where TASKS.md, CLAUDE.md and requirements.txt live).
# This runner NEVER commits, stashes or runs any git command, and NEVER installs packages.
# All changes stay in your working folder for you to review and commit yourself.
if ($PSScriptRoot) { Set-Location -LiteralPath $PSScriptRoot }
$ErrorActionPreference = "Continue"
$startScript = Join-Path $LocalLLMDir "start.ps1"
$stopScript = Join-Path $LocalLLMDir "stop.ps1"
$claudeLocal = Join-Path $LocalLLMDir "claude-local.cmd"

# claude-local.cmd reads these: CLAUDE_LOCAL_STRICT_MCP drops all your other MCP servers,
# CLAUDE_LOCAL_NO_RAG drops the book search. The old values are put back at the end.
$oldStrictMcp = $env:CLAUDE_LOCAL_STRICT_MCP
$oldNoRag = $env:CLAUDE_LOCAL_NO_RAG
$env:CLAUDE_LOCAL_STRICT_MCP = "1"
if ($UseBookSearch) { Remove-Item Env:CLAUDE_LOCAL_NO_RAG -ErrorAction SilentlyContinue }
else { $env:CLAUDE_LOCAL_NO_RAG = "1" }

$script:Py = $null
$script:VenvRoot = $null
$script:SavedEnv = @{}
$script:HasRuff = $false
$script:HasPytest = $false
$script:HasMypy = $false
$script:ServerStartAttempted = $false
$script:ImportCheckFile = $null

# Tries every module of src/ (not tests) to import. Catches syntax errors, missing packages and circular imports.
$script:ImportCheckSource = @'
import importlib
import os
import sys
import traceback

root = sys.argv[1]
failed = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted(d for d in dirnames if d not in ("__pycache__", "tests"))
    for name in sorted(filenames):
        if not name.endswith(".py") or name == "__main__.py":
            continue
        rel = os.path.relpath(os.path.join(dirpath, name), root)[:-3]
        parts = rel.split(os.sep)
        if parts[-1] == "__init__":
            parts = parts[:-1]
        if not parts:
            continue
        module = ".".join(parts)
        try:
            importlib.import_module(module)
        except BaseException:
            failed.append(module)
            print("IMPORT ERROR in " + module)
            traceback.print_exc()
sys.exit(1 if failed else 0)
'@

# ---------------------------------------------------------------- helpers

function Get-NextTaskIndex {
    $lines = @(Get-Content $TasksFile)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*- \[ \]') { return $i }
    }
    return -1
}

function Set-TaskMark([int]$index, [string]$mark) {
    $lines = @(Get-Content $TasksFile)
    $lines[$index] = $lines[$index] -replace '^(\s*)- \[ \]', "`$1- [$mark]"
    Set-Content -Path $TasksFile -Value $lines -Encoding UTF8
}

function Resolve-VenvPython {
    foreach ($base in @($VenvName, (Join-Path ".." $VenvName))) {
        $py = Join-Path $base "Scripts\python.exe"
        if (Test-Path $py) { return (Resolve-Path $py).Path }
    }
    return $null
}

# Makes this PowerShell process (and the agent started from it) use the venv, with src/ and vendor/ importable.
# Nothing is changed outside this process. Exit-PythonEnv puts every value back.
function Enter-PythonEnv {
    $names = @('PATH', 'VIRTUAL_ENV', 'PYTHONPATH', 'PYTHONUTF8', 'PYTHONDONTWRITEBYTECODE', 'MYPYPATH')
    foreach ($n in $names) { $script:SavedEnv[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
    $srcFull = (Resolve-Path $SourceDir).Path
    $paths = @($srcFull)
    if (Test-Path $VendorDir) { $paths += (Resolve-Path $VendorDir).Path }
    $env:VIRTUAL_ENV = $script:VenvRoot
    $env:PATH = (Join-Path $script:VenvRoot "Scripts") + ";" + $env:PATH
    $env:PYTHONPATH = ($paths -join ";")
    $env:MYPYPATH = ($paths -join ";")
    $env:PYTHONUTF8 = "1"
    $env:PYTHONDONTWRITEBYTECODE = "1"
}

function Exit-PythonEnv {
    foreach ($k in @($script:SavedEnv.Keys)) {
        [Environment]::SetEnvironmentVariable($k, $script:SavedEnv[$k], 'Process')
    }
}

function Test-PyModule([string]$name) {
    & $script:Py -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec('$name') else 1)" 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Get-TestFiles {
    return @(Get-ChildItem -Path $SourceDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '[\\/]__pycache__[\\/]' -and
            ($_.Name -like 'test_*.py' -or $_.Name -like '*_test.py')
        })
}

# Path -> "size|last write time" for the files the agent could touch (root files, src, vendor), ignoring caches.
# Used instead of git to see whether an attempt changed anything. The venv is never scanned.
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
            $_.Name -notin @('TASKS.md', 'CODEBASE_MAP.md', 'CODEBASE_MAP.md.bak')
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

# Import check, then ruff, then mypy (optional), then pytest. Tools that are not installed are skipped.
function Invoke-Verify {
    $out = & $script:Py $script:ImportCheckFile (Resolve-Path $SourceDir).Path 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        return @{ Ok = $false; Stage = "import check"; Output = $out }
    }
    if ($script:HasRuff -and -not $SkipLint) {
        $out = & $script:Py -m ruff check $SourceDir --no-cache 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            return @{ Ok = $false; Stage = "ruff"; Output = $out }
        }
    }
    if ($UseMypy -and $script:HasMypy) {
        $out = & $script:Py -m mypy $SourceDir --explicit-package-bases --ignore-missing-imports 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            return @{ Ok = $false; Stage = "mypy"; Output = $out }
        }
    }
    if ($script:HasPytest -and (Get-TestFiles).Count -gt 0) {
        $out = & $script:Py -m pytest $SourceDir -q -p no:cacheprovider 2>&1 | Out-String
        # Exit code 5 means "no tests collected", which is not a failure.
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 5) {
            return @{ Ok = $false; Stage = "pytest"; Output = $out }
        }
    }
    return @{ Ok = $true; Stage = "done"; Output = "" }
}

function Get-Failures([string]$text) {
    $pattern = 'IMPORT ERROR|Traceback|\w+Error\b|^\s*File ".*", line \d+|:\d+:\d+: [A-Z]+\d+|^FAILED |^ERROR |^E\s{3}|\bassert\b|error:'
    $lines = $text -split "`r?`n" | Where-Object { $_ -match $pattern } | Select-Object -Unique -First 60
    return ($lines -join "`n")
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
        $finished = $proc.WaitForExit($AttemptTimeoutMinutes * 60 * 1000)
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

# Local model server ready? If not, try to (re)start it once.
function Confirm-ModelServer {
    & $startScript -CheckOnly | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }
    Write-Host "The local model server is down. Restarting it..." -ForegroundColor Yellow
    & $startScript
    return ($LASTEXITCODE -eq 0)
}

# Keep Windows from sleeping while this script runs (overnight runs).
Add-Type -Namespace LocalLLM -Name Power -MemberDefinition `
    '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
[LocalLLM.Power]::SetThreadExecutionState([uint32]2147483649) | Out-Null   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED

# ---------------------------------------------------------------- main

try {
    # --- Preflight ---
    if (-not (Test-Path $TasksFile)) { Write-Host "Missing $TasksFile"; exit 1 }
    if (-not (Test-Path $SourceDir)) { Write-Host "Missing $SourceDir folder. Run this from the project root."; exit 1 }
    if (-not (Test-Path $RequirementsFile)) { Write-Host "Missing $RequirementsFile"; exit 1 }
    if (-not (Test-Path "CLAUDE.md")) { Write-Host "Missing CLAUDE.md"; exit 1 }
    if (-not (Test-Path ".claude\settings.json")) { Write-Host "Missing .claude\settings.json (the permission rules)."; exit 1 }
    if (-not (Test-Path $claudeLocal)) { Write-Host "$claudeLocal not found. Run $LocalLLMDir\setup.ps1 first."; exit 1 }
    if (-not (Get-Command claude.exe, claude.cmd -ErrorAction SilentlyContinue)) { Write-Host "claude (Claude Code CLI) not found on PATH."; exit 1 }

    $script:Py = Resolve-VenvPython
    if (-not $script:Py) {
        Write-Host "Could not find $VenvName\Scripts\python.exe (looked here and one folder above). Pass -VenvName or create the venv." -ForegroundColor Red
        exit 1
    }
    $script:VenvRoot = Split-Path (Split-Path $script:Py)
    Enter-PythonEnv

    $pyVersion = (& $script:Py --version 2>&1 | Out-String).Trim()
    Write-Host "Using $pyVersion from $script:VenvRoot" -ForegroundColor DarkGray
    if ($pyVersion -notmatch '3\.12') { Write-Host "Warning: expected Python 3.12, found '$pyVersion'." -ForegroundColor Yellow }

    # Which checkers are installed? Nothing is ever installed by this script.
    $script:HasRuff = Test-PyModule "ruff"
    $script:HasPytest = Test-PyModule "pytest"
    $script:HasMypy = Test-PyModule "mypy"
    if (-not $script:HasRuff -and -not $SkipLint) { Write-Host "ruff is not installed in the venv: linting is skipped. To enable it, run 'pip install ruff' yourself and add it to $RequirementsFile." -ForegroundColor Yellow }
    if (-not $script:HasPytest) { Write-Host "pytest is not installed in the venv: tests are skipped. To enable them, run 'pip install pytest' yourself and add it to $RequirementsFile." -ForegroundColor Yellow }
    if ($UseMypy -and -not $script:HasMypy) { Write-Host "-UseMypy was given but mypy is not installed in the venv: skipped." -ForegroundColor Yellow }

    # Informational only: are the installed packages consistent with each other?
    $pipCheck = & $script:Py -m pip check 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Host "pip check reports problems with the installed packages:`n$pipCheck" -ForegroundColor Yellow }

    $script:ImportCheckFile = Join-Path ([System.IO.Path]::GetTempPath()) "aisim_import_check.py"
    Set-Content -Path $script:ImportCheckFile -Value $script:ImportCheckSource -Encoding ASCII

    $script:ServerStartAttempted = $true
    & $startScript
    if ($LASTEXITCODE -ne 0) { Write-Host "The local model server could not be started." -ForegroundColor Red; exit 1 }

    Write-Host "Checking that the project passes before starting..." -ForegroundColor Cyan
    $pre = Invoke-Verify
    if (-not $pre.Ok) {
        Write-Host "The project does not pass '$($pre.Stage)' before any task ran. Fix that first:" -ForegroundColor Red
        Write-Host (Get-Failures $pre.Output)
        exit 1
    }

    # --- Create codebase map once if missing (not committed) ---
    if (-not (Test-Path "CODEBASE_MAP.md")) {
        Write-Host "Creating CODEBASE_MAP.md (one time only)..." -ForegroundColor Cyan
        $mapPrompt = @"
Read $RequirementsFile (package names and versions only) and every .py file under $SourceDir (skip __pycache__ and the tests folder), and create CODEBASE_MAP.md. Do not change any other file. Do not run any git command. Do not run any command at all.
Format:
1. One line with the Python version (3.12) and the packages from $RequirementsFile.
2. A short 'Boot flow' tree: entry points (files with an if __name__ == "__main__" guard), what they call, and how the folders (modules) depend on each other.
3. 'Folders and classes': one heading per folder under $SourceDir (import name = folder name), then one short line per class and per public top-level function: base class, purpose, key public methods, which file.
Keep it concise. No code listings.
"@
        $r = Invoke-Agent $mapPrompt
        Write-Host $r.Output
        if (-not (Test-Path "CODEBASE_MAP.md")) {
            Write-Host "CODEBASE_MAP.md was not created; continuing without it." -ForegroundColor Yellow
        }
    }

    # --- Main loop ---
    while ($true) {
        $idx = Get-NextTaskIndex
        if ($idx -lt 0) { Write-Host "`nNo unchecked tasks left."; break }

        $lines = @(Get-Content $TasksFile)
        $task = ($lines[$idx] -replace '^\s*- \[ \]\s*', '').Trim()
        $shortTask = if ($task.Length -gt 100) { $task.Substring(0, 100) + "..." } else { $task }
        Write-Host "`n=== TASK: $shortTask ===" -ForegroundColor Cyan

        $taskStart = Get-ProjectSnapshot
        $success = $false
        $needsPackage = $null
        $lastErrors = ""

        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            Write-Host "Attempt $attempt of $MaxRetries... ($(Get-Date -Format HH:mm))" -ForegroundColor Yellow

            $prompt = @"
Follow CLAUDE.md. Implement ONLY this task:

$task

Write Python code only, under $SourceDir/. Do not run any git command. Do not commit anything.
Do not edit TASKS.md, CLAUDE.md, $RequirementsFile, or anything in .claude/, $VendorDir/ or $VenvName/. Never install, remove or upgrade packages (no pip). If the task needs a package that is not in $RequirementsFile, write no code and put 'NEEDS_PACKAGE: <package> - <why>' on its own line in your reply.
The venv is already active and $SourceDir/ and $VendorDir/ are already on the import path: use plain 'python' and absolute imports from the folder names.
Then check your work and fix all errors until everything passes: run 'python -m ruff check $SourceDir' if ruff is installed, 'python -m pytest $SourceDir -q' if pytest is installed and tests exist, and an import check ('python -c "import folder.module"') for each module you created or changed.
When done, update CODEBASE_MAP.md for any files, classes or public functions added, removed, or changed (one short line each).
"@
            if ($lastErrors) {
                $prompt += "`n`nA previous attempt left these errors. Fix them:`n$lastErrors"
            }

            $before = Get-ProjectSnapshot
            $result = Invoke-Agent $prompt
            Write-Host $result.Output
            if ($result.TimedOut) {
                Write-Host "Attempt timed out after $AttemptTimeoutMinutes minutes." -ForegroundColor Red
            }

            if (-not (Confirm-ModelServer)) {
                Write-Host "`nThe local model server is down and could not be restarted. Rerun later to resume this task." -ForegroundColor Red
                Write-Host "Any half-done changes are still in the folder." -ForegroundColor Red
                exit 2
            }

            # The task needs a package that is not installed. Retrying will not help.
            $m = [regex]::Match([string]$result.Output, '(?m)^\s*NEEDS_PACKAGE:\s*(.+)$')
            if ($m.Success) {
                $needsPackage = $m.Groups[1].Value.Trim()
                break
            }

            # A local model sometimes "finishes" without touching anything. That is not a success.
            $after = Get-ProjectSnapshot
            if ((Get-ChangedFiles $before $after).Count -eq 0 -and (Get-ChangedFiles $taskStart $after).Count -eq 0) {
                $lastErrors = "The previous attempt made no file changes at all. Actually create or edit the files the task asks for."
                Write-Host "No changes were made." -ForegroundColor Red
                continue
            }

            # Independent check, don't trust the model's word for it
            $verify = Invoke-Verify
            if ($verify.Ok) { $success = $true; break }

            $lastErrors = "$($verify.Stage) failed:`n" + (Get-Failures $verify.Output)
            Write-Host $lastErrors -ForegroundColor Red
        }

        $changedFiles = Get-ChangedFiles $taskStart (Get-ProjectSnapshot)
        if ($success) {
            Set-TaskMark $idx "x"
            Write-Host "Done. The checks pass. Nothing was committed." -ForegroundColor Green
        }
        elseif ($needsPackage) {
            Set-TaskMark $idx "!"
            Write-Host "The task needs a package that is not installed: $needsPackage" -ForegroundColor Red
            Write-Host "Install it yourself in $VenvName (pip install ...), add it to $RequirementsFile, change this task's [!] back to [ ], and rerun." -ForegroundColor Red
        }
        else {
            Set-TaskMark $idx "!"
            Write-Host "Task failed after $MaxRetries attempts. Its changes are left in the folder for you to look at." -ForegroundColor Red
        }
        if ($changedFiles.Count -gt 0) {
            Write-Host "Files created or changed:"
            $changedFiles | ForEach-Object { Write-Host "  $_" }
        }

        if (-not $success -and -not $ContinueOnFailure) {
            Write-Host "`nStopping because later tasks may depend on this one. Fix it, change its [!] back to [ ], and rerun." -ForegroundColor Red
            Write-Host "Use -ContinueOnFailure to skip failed tasks instead."
            exit 3
        }
    }

    Write-Host "`nAll done. Review the changes and commit them yourself."
}
finally {
    [LocalLLM.Power]::SetThreadExecutionState([uint32]2147483648) | Out-Null   # allow sleep again
    if ($script:ImportCheckFile) { Remove-Item $script:ImportCheckFile -ErrorAction SilentlyContinue }
    Exit-PythonEnv
    $env:CLAUDE_LOCAL_STRICT_MCP = $oldStrictMcp
    $env:CLAUDE_LOCAL_NO_RAG = $oldNoRag

    # Always shut the local model server down at the end (also after a failure), unless asked not to.
    if ($script:ServerStartAttempted -and -not $KeepServerRunning) {
        if (Test-Path $stopScript) {
            Write-Host "Stopping the local model server..." -ForegroundColor Cyan
            & $stopScript
        }
        else {
            Write-Host "$stopScript not found; the local model server is still running." -ForegroundColor Yellow
        }
    }
}
