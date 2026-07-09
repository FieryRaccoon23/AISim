@echo off
setlocal enabledelayedexpansion

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
REM Edit the "git ls-files" pattern list below to match the file
REM types you actually want included. Excludes vendor/, NOTES.md
REM itself, and Aider's own housekeeping files.
REM
REM --no-auto-commits: Aider edits NOTES.md but does NOT commit it.
REM Review with `git diff NOTES.md`, commit yourself when ready.
REM
REM Usage: double-click, or run from a terminal in the project root:
REM   update_notes.bat

echo Updating NOTES.md via Aider + LM Studio...
echo.

set FILEARGS=

for /f "delims=" %%F in ('git ls-files -- "*.py" "*.yaml" "*.yml" "*.txt" "*.toml" "*.ini" ":!:vendor/*" ":!:NOTES.md" ":!:.aider*"') do (
    set FILEARGS=!FILEARGS! --file "%%F"
)

if "!FILEARGS!"=="" (
    echo No matching tracked files found. Check the git ls-files patterns in this script.
    pause
    exit /b 1
)

echo Files being included:
git ls-files -- "*.py" "*.yaml" "*.yml" "*.txt" "*.toml" "*.ini" ":!:vendor/*" ":!:NOTES.md" ":!:.aider*"
echo.

aider --openai-api-base http://localhost:1234/v1 ^
      --openai-api-key lm-studio ^
      --model openai/qwen3-coder-30b ^
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
