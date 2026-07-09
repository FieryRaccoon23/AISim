@echo off
setlocal enabledelayedexpansion

REM Force UTF-8 console + Python I/O encoding. Without this, Aider
REM crashes with UnicodeEncodeError on Windows whenever it tries to
REM print a file/message containing a character the legacy cp1252
REM codepage can't represent (e.g. checkmarks, smart quotes, emoji).
chcp 65001 >nul
set PYTHONIOENCODING=utf-8

REM update_notes.bat
REM Runs Aider once, non-interactively, to create/update NOTES.md
REM based on the current state of the codebase. Uses your local
REM LM Studio server (Qwen3 Coder 30B) as the model backend.
REM
REM Instead of a hardcoded --file list (which breaks the moment you
REM add/delete/rename files), this script asks git for the CURRENT
REM list of tracked files matching common source/config extensions,
REM and builds the --file arguments dynamically every run.
REM
REM Two layers of protection against passing a directory to --file:
REM   1. Submodules are excluded by reading .gitmodules directly and
REM      skipping any path git lists that matches a known submodule.
REM   2. Fallback: for every remaining path, convert forward slashes to
REM      backslashes and test "path\NUL" - this only resolves if the
REM      path is a real directory (NUL is a device that exists inside
REM      every directory, never inside a file). The backslash
REM      conversion matters: "vendor/drawflow\NUL" (mixed separators)
REM      does not reliably resolve on Windows, but
REM      "vendor\drawflow\NUL" does.
REM
REM Edit the "git ls-files" pattern list to match the file types you
REM actually want included. Excludes vendor/, NOTES.md itself, and
REM Aider's own housekeeping files.
REM
REM --no-auto-commits: Aider edits NOTES.md but does NOT commit it.
REM Review with `git diff NOTES.md`, commit yourself when ready.
REM
REM Usage: double-click, or run from a terminal in the project root:
REM   update_notes.bat

echo Updating NOTES.md via Aider + LM Studio...
echo.

set FILEARGS=
set INCLUDED=
set SKIPPED=

REM --- Build list of submodule paths from .gitmodules (if any) ---
set SUBMODULES=
if exist ".gitmodules" (
    for /f "tokens=2 delims== " %%S in ('git config --file .gitmodules --get-regexp path') do (
        set SUBMODULES=!SUBMODULES! %%S
    )
)

REM --- Walk tracked files matching our extensions, skip submodules/dirs ---
for /f "delims=" %%F in ('git ls-files -- "*.py" "*.yaml" "*.yml" "*.txt" "*.toml" "*.ini" ":!:vendor/*" ":!:NOTES.md" ":!:.aider*"') do (
    set "IS_SUBMODULE="
    for %%S in (!SUBMODULES!) do (
        if /i "%%F"=="%%S" set "IS_SUBMODULE=1"
    )

    set "NORMALIZED=%%F"
    set "NORMALIZED=!NORMALIZED:/=\!"

    if defined IS_SUBMODULE (
        set SKIPPED=!SKIPPED! %%F
    ) else if exist "!NORMALIZED!\NUL" (
        set SKIPPED=!SKIPPED! %%F
    ) else (
        set FILEARGS=!FILEARGS! --file "%%F"
        set INCLUDED=!INCLUDED! %%F
    )
)

echo Files being included:
if "!INCLUDED!"=="" (
    echo   ^(none^)
) else (
    for %%A in (!INCLUDED!) do echo   %%A
)
echo.
echo Skipped ^(submodules/directories, not passed to --file^):
if "!SKIPPED!"=="" (
    echo   ^(none^)
) else (
    for %%A in (!SKIPPED!) do echo   %%A
)
echo.

if "!FILEARGS!"=="" (
    echo No files ended up in the include list - see the breakdown above
    echo to see whether everything was skipped or git ls-files found nothing.
    echo Check the git ls-files patterns in this script if that looks wrong.
    pause
    exit /b 1
)

aider --openai-api-base http://localhost:1234/v1 ^
      --openai-api-key lm-studio ^
      --model openai/qwen3-coder-30b ^
      --edit-format diff ^
      --yes-always --no-stream --no-auto-commits ^
      !FILEARGS! ^
      --message "Update NOTES.md to reflect the current project structure, module responsibilities, and design decisions. Create it if it doesn't exist."

echo.
echo Done. NOTES.md was updated but NOT committed to git.
echo Review the change with: git diff NOTES.md
echo Commit it yourself when ready:
echo   git add NOTES.md
echo   git commit -m "docs: update NOTES.md"
echo.
pause
