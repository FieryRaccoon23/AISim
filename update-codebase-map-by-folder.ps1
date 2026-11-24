param(
    # The shared local-model folder (Strata, Headroom, claude-local.cmd). Same as run-tasks.ps1.
    [string]$LocalLLMDir = "D:\LocalLLM",
    # One agent run (one folder, or one chunk of a big folder) is killed after this many minutes.
    [int]$TimeoutMinutes = 30,
    # Max size of the .py files given to ONE agent run, in KB. About 4 KB of code = 1k tokens, so 100 KB
    # is roughly 25k tokens, which leaves room for CLAUDE.md and the model's answer in a 64k context.
    # A folder bigger than this is split into several runs automatically.
    [int]$MaxChunkKB = 100,
    # Tries per folder (or chunk) when the answer is empty or incomplete.
    [int]$MaxAttempts = 2,
    [string]$SourceDir = "src",
    [string]$VendorDir = "vendor",
    # Only read for package names and versions.
    [string]$RequirementsFile = "requirements.txt",
    [string]$PythonVersion = "3.12.0",
    # Skip the final short "Boot flow" step (it reads the finished map, not the code).
    [switch]$SkipBootFlow,
    # Leave the local model server running at the end, even if this script started it.
    [switch]$KeepServerRunning
)

# Run from the project root (D:\AISim\AISim).
# One small agent run per folder under src. The agent only READS and answers with a bullet list;
# this script writes CODEBASE_MAP.md itself, and only at the very end. If anything fails, the existing
# CODEBASE_MAP.md is left exactly as it was. Never runs git, never installs anything, never runs Python.
if ($PSScriptRoot) { Set-Location -LiteralPath $PSScriptRoot }
$ErrorActionPreference = "Continue"
$startScript = Join-Path $LocalLLMDir "start.ps1"
$stopScript = Join-Path $LocalLLMDir "stop.ps1"
$claudeLocal = Join-Path $LocalLLMDir "claude-local.cmd"
$mapFile = "CODEBASE_MAP.md"

$oldStrictMcp = $env:CLAUDE_LOCAL_STRICT_MCP
$oldNoRag = $env:CLAUDE_LOCAL_NO_RAG
$env:CLAUDE_LOCAL_STRICT_MCP = "1"
$env:CLAUDE_LOCAL_NO_RAG = "1"

# ---------------------------------------------------------------- helpers

function Get-Rel([string]$fullPath) {
    $root = (Get-Location).Path.TrimEnd('\') + '\'
    return $fullPath.Replace($root, '')
}

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

# The .py files that get described: caches, tests and tiny (empty) __init__.py files are left out.
function Get-MapFiles([string]$path, [bool]$recurse) {
    $p = @{ Path = $path; File = $true; Filter = '*.py'; ErrorAction = 'SilentlyContinue' }
    if ($recurse) { $p.Recurse = $true }
    return @(Get-ChildItem @p |
        Where-Object {
            (Get-Rel $_.FullName) -notmatch '(^|[\\/])(__pycache__|tests)[\\/]' -and
            -not ($_.Name -eq '__init__.py' -and $_.Length -lt 200)
        } | Sort-Object FullName)
}

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

function Confirm-ModelServer {
    & $startScript -CheckOnly | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }
    Write-Host "The local model server is down. Restarting it..." -ForegroundColor Yellow
    & $startScript
    return ($LASTEXITCODE -eq 0)
}

# Splits a list of files into chunks whose total size stays under the limit (a single huge file gets its own chunk).
function Split-Chunks($files, [long]$limitBytes) {
    $chunks = @()
    $cur = @()
    $size = 0
    foreach ($f in $files) {
        if ($cur.Count -gt 0 -and ($size + $f.Length) -gt $limitBytes) {
            $chunks += , $cur
            $cur = @()
            $size = 0
        }
        $cur += $f
        $size += $f.Length
    }
    if ($cur.Count -gt 0) { $chunks += , $cur }
    return , $chunks
}

# Keeps only the markdown bullet lines of an agent answer, so any chatter around them is dropped.
function Get-BulletLines([string]$text) {
    $out = @()
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match '^[-*]\s+\S') {
            $out += ($t -replace '^[*]\s+', '- ')
        }
    }
    return $out
}

# Public top-level classes and functions of the files. A file with none is expected by its file name.
function Get-ExpectedNames($files) {
    $expected = @()
    foreach ($f in $files) {
        $code = Get-Content $f.FullName -Raw -Encoding UTF8
        if (-not $code) { $code = "" }
        $found = @([regex]::Matches($code, '(?m)^(?:async\s+def|def|class)\s+([A-Za-z]\w*)') | ForEach-Object { $_.Groups[1].Value })
        if ($found.Count -gt 0) { $expected += $found } else { $expected += $f.BaseName }
    }
    return @($expected | Sort-Object -Unique)
}

$script:FolderPromptTemplate = @'
Your ONLY job is to describe Python code. Read ONLY these files:
{{FILES}}

Do not read any other file. Do not edit, create or delete any file. Do not run any command (no git, no python, no pip).

Reply with ONLY a markdown bullet list: nothing before it, nothing after it, no code blocks, no headings.
One bullet per class and one per public top-level function (names not starting with an underscore) in those files, in this format:
- ClassName(BaseClass) [file.py] - purpose in a few words. Public: method1, method2. Fields: field1, field2
- function_name [file.py] - purpose in a few words.
Leave out "Public:" or "Fields:" when there is nothing to list. For a dataclass write "dataclass" after the purpose and list its fields instead of Public. For an Enum list its members instead of Public.
A file with no class and no public function gets one bullet: - module_name [file.py] - purpose in a few words.
If a file is inside a subfolder, start its bullet with the subfolder in brackets, for example: - [combat] ClassName(BaseClass) [file.py] : ...
Keep each bullet under 250 characters. No code listings.
'@

$script:BootPromptTemplate = @'
Below is a map of a Python simulation project (one bullet per class or function, grouped by folder, each folder with the folders it depends on). Do not read any file, do not run any command. Use ONLY the map below.
Write a short 'Boot flow' tree (at most 25 lines): entry points, what they create and call, how the main loop or lifecycle runs, and how the folders depend on each other. Leave out anything the map does not support.
Reply with ONLY the tree inside one code block (three backticks), nothing before or after it.

{{MAP}}
'@

# Describes one chunk of files. Returns the bullet lines, or $null when it failed.
function Invoke-ChunkMap([string]$label, $files) {
    $fileList = ($files | ForEach-Object { "- " + (Get-Rel $_.FullName) }) -join "`n"
    $prompt = $script:FolderPromptTemplate.Replace('{{FILES}}', $fileList)

    $best = @()
    $expected = Get-ExpectedNames $files
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Host "  $label : attempt $attempt of $MaxAttempts ($(Get-Date -Format HH:mm))..." -ForegroundColor Yellow
        $r = Invoke-Agent $prompt
        if ($r.TimedOut) {
            Write-Host "  Timed out after $TimeoutMinutes minutes." -ForegroundColor Red
            if (-not (Confirm-ModelServer)) { return $null }
            continue
        }
        $lines = @(Get-BulletLines $r.Output)
        if ($lines.Count -gt $best.Count) { $best = $lines }
        $joined = $lines -join "`n"
        $missing = @($expected | Where-Object { $joined -notmatch [regex]::Escape($_) })
        if ($lines.Count -gt 0 -and $missing.Count -eq 0) { return $lines }
        if ($lines.Count -eq 0) { Write-Host "  No bullet list in the answer." -ForegroundColor Red }
        else { Write-Host "  Not mentioned: $($missing -join ', ')" -ForegroundColor Red }
    }
    if ($best.Count -gt 0) {
        $joined = $best -join "`n"
        $missing = @($expected | Where-Object { $joined -notmatch [regex]::Escape($_) })
        Write-Host "  Using the best answer; missing names: $($missing -join ', ')" -ForegroundColor Yellow
        return $best
    }
    return $null
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

    # --- Find the folders (each top-level folder under src is one unit, subfolders included) ---
    $groups = @()
    $rootFiles = Get-MapFiles $SourceDir $false
    if ($rootFiles.Count -gt 0) { $groups += @{ Name = "(src root)"; Files = $rootFiles } }
    foreach ($dir in (Get-ChildItem -Path $SourceDir -Directory | Where-Object { $_.Name -notin @('__pycache__', 'tests') } | Sort-Object Name)) {
        $files = Get-MapFiles $dir.FullName $true
        if ($files.Count -gt 0) { $groups += @{ Name = $dir.Name; Files = $files } }
    }
    if ($groups.Count -eq 0) { Write-Host "No .py files found under $SourceDir."; exit 1 }
    $groupNames = @($groups | Where-Object { $_.Name -ne "(src root)" } | ForEach-Object { $_.Name })

    # --- Header: Python, packages, vendor, entry points (read by this script, not the model) ---
    $reqs = @(Get-Content $RequirementsFile -Encoding UTF8 |
        ForEach-Object { ($_ -replace '\s+#.*$', '').Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.StartsWith('-') })

    $vendorItems = @()
    if (Test-Path $VendorDir) {
        $vendorItems = @(Get-ChildItem -Path $VendorDir -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne '__pycache__' -and ($_.PSIsContainer -or $_.Extension -eq '.py') } |
            ForEach-Object { $_.BaseName })
    }

    $entryPoints = @(Get-ChildItem -Path $SourceDir -Recurse -File -Filter *.py -ErrorAction SilentlyContinue |
        Where-Object { (Get-Rel $_.FullName) -notmatch '(^|[\\/])(__pycache__|tests)[\\/]' } |
        Where-Object { (Get-Content $_.FullName -Raw -Encoding UTF8) -match '(?m)^if\s+__name__\s*==\s*[''"]__main__[''"]' } |
        ForEach-Object { (Get-Rel $_.FullName).Replace('\', '/') })

    $header = New-Object System.Text.StringBuilder
    [void]$header.AppendLine("- Python $PythonVersion (venv_AISim). Code in $SourceDir/, each folder is a package imported by its folder name.")
    if ($reqs.Count -gt 0) { [void]$header.AppendLine("- Packages ($RequirementsFile): $($reqs -join ', ')") }
    if ($vendorItems.Count -gt 0) { [void]$header.AppendLine("- Vendor code (read-only, in $VendorDir/): $($vendorItems -join ', ')") }
    if ($entryPoints.Count -gt 0) { [void]$header.AppendLine("- Entry points: $($entryPoints -join ', ')") }
    [void]$header.AppendLine("- Tests: $SourceDir/tests (not listed below)")

    # --- Make sure the local model server is up ---
    & $startScript -CheckOnly | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Starting the local model server..." -ForegroundColor Cyan
        & $startScript
        if ($LASTEXITCODE -ne 0) { Write-Host "The local model server could not be started." -ForegroundColor Red; exit 1 }
        $weStartedServer = $true
    }

    # --- One agent run per folder (or per chunk of a big folder) ---
    $snapshotBefore = Get-ProjectSnapshot
    $sections = New-Object System.Text.StringBuilder
    $limitBytes = [long]$MaxChunkKB * 1024
    $index = 0
    foreach ($g in $groups) {
        $index++
        $totalKB = [math]::Round((($g.Files | Measure-Object -Property Length -Sum).Sum) / 1024, 1)
        Write-Host "[$index/$($groups.Count)] $($g.Name): $($g.Files.Count) file(s), $totalKB KB" -ForegroundColor Cyan

        $chunks = Split-Chunks $g.Files $limitBytes
        $allLines = @()
        $c = 0
        foreach ($chunk in $chunks) {
            $c++
            $label = if ($chunks.Count -gt 1) { "$($g.Name) (part $c of $($chunks.Count))" } else { $g.Name }
            $lines = Invoke-ChunkMap $label $chunk
            if ($null -eq $lines) {
                Write-Host "Could not map $label. $mapFile was NOT changed." -ForegroundColor Red
                exit 3
            }
            $allLines += $lines
        }

        # Which other folders does this folder import? (read by this script with a regex, not by the model)
        $depends = @()
        if ($g.Name -ne "(src root)") {
            $imported = @{}
            foreach ($f in $g.Files) {
                $code = Get-Content $f.FullName -Raw -Encoding UTF8
                if (-not $code) { continue }
                foreach ($m in [regex]::Matches($code, '(?m)^\s*(?:from|import)\s+([A-Za-z_]\w*)')) {
                    $imported[$m.Groups[1].Value] = $true
                }
            }
            $depends = @($groupNames | Where-Object { $_ -ne $g.Name -and $imported.ContainsKey($_) })
        }

        $title = if ($g.Name -eq "(src root)") { "## src root (files directly in $SourceDir, imported by file name)" }
                 else { "## $($g.Name) ($SourceDir/$($g.Name), import: $($g.Name))" }
        [void]$sections.AppendLine($title)
        if ($depends.Count -gt 0) { [void]$sections.AppendLine("Depends on: $($depends -join ', ')") }
        foreach ($l in $allLines) { [void]$sections.AppendLine($l) }
        [void]$sections.AppendLine("")
    }

    # --- The agent must not have touched any project file ---
    $changed = Get-ChangedFiles $snapshotBefore (Get-ProjectSnapshot)
    if ($changed.Count -gt 0) {
        Write-Host "The agent changed project files, which it must not do:" -ForegroundColor Red
        $changed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Write-Host "$mapFile was NOT changed. Review those files." -ForegroundColor Red
        exit 4
    }

    # --- Optional boot flow, written from the finished map only (small input) ---
    $bootText = ""
    if (-not $SkipBootFlow) {
        Write-Host "Writing the boot flow from the map..." -ForegroundColor Cyan
        $mapForBoot = $header.ToString() + "`n" + $sections.ToString()
        $bootPrompt = $script:BootPromptTemplate.Replace('{{MAP}}', $mapForBoot)
        $r = Invoke-Agent $bootPrompt
        $m = [regex]::Match($r.Output, '(?s)```[a-zA-Z]*\r?\n(.*?)```')
        if ($m.Success -and $m.Groups[1].Value.Trim().Length -gt 0) {
            $bootText = "## Boot flow`n" + '```' + "`n" + $m.Groups[1].Value.TrimEnd() + "`n" + '```' + "`n"
        }
        else {
            Write-Host "No usable boot flow came back; leaving it out." -ForegroundColor Yellow
        }
    }

    # --- Write the map (only now, so a failed run never damages the old one) ---
    $final = New-Object System.Text.StringBuilder
    [void]$final.AppendLine("# Codebase map")
    [void]$final.AppendLine("Generated by update-codebase-map-by-folder.ps1 from $SourceDir (Python only). One line per class or public function.")
    [void]$final.AppendLine("")
    [void]$final.Append($header.ToString())
    [void]$final.AppendLine("")
    if ($bootText) { [void]$final.AppendLine($bootText) }
    [void]$final.Append($sections.ToString())

    $fullPath = Join-Path (Get-Location).Path $mapFile
    [System.IO.File]::WriteAllText($fullPath, $final.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "`n$mapFile written ($($groups.Count) folder sections). Nothing else was changed and nothing was committed." -ForegroundColor Green
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
