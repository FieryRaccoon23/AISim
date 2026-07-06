@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  Blueprint UI project setup script (Windows)
REM  - Initializes git (if needed)
REM  - Adds/updates the litegraph.js fork as a submodule
REM  - Sets up a Python virtual environment and installs deps
REM ============================================================

REM --- EDIT THESE TWO VALUES FOR YOUR SETUP ---
set FORK_URL=https://github.com/YOUR_USERNAME/litegraph.js.git
set SUBMODULE_PATH=vendor/litegraph
REM ----------------------------------------------

echo.
echo === Blueprint UI Setup ===
echo.

REM 1. Make sure we're in a git repo
if not exist ".git" (
    echo No git repo found. Initializing one...
    git init
) else (
    echo Git repo already initialized.
)

REM 2. Add the litegraph submodule if it isn't already there
if exist "%SUBMODULE_PATH%\.git" (
    echo Submodule already present at %SUBMODULE_PATH%, skipping add.
) else (
    echo Adding litegraph.js fork as a submodule from %FORK_URL% ...
    git submodule add %FORK_URL% %SUBMODULE_PATH%
)

REM 3. Make sure submodule content is checked out
echo Initializing and updating submodules...
git submodule update --init --recursive

REM 4. Add upstream remote inside the submodule so you can pull updates later
pushd %SUBMODULE_PATH%
git remote get-url upstream >nul 2>&1
if errorlevel 1 (
    echo Adding "upstream" remote (jagenjo/litegraph.js) inside submodule...
    git remote add upstream https://github.com/jagenjo/litegraph.js.git
) else (
    echo Upstream remote already configured.
)
popd

REM 5. Python virtual environment
if not exist "venv" (
    echo Creating Python virtual environment...
    python -m venv venv
) else (
    echo Virtual environment already exists.
)

echo Installing Python dependencies...
call venv\Scripts\activate.bat
pip install -r requirements.txt

echo.
echo === Setup complete ===
echo.
echo To run the app:
echo   venv\Scripts\activate
echo   uvicorn main:app --reload
echo.
echo To pull upstream litegraph.js updates into your fork later:
echo   cd %SUBMODULE_PATH%
echo   git fetch upstream
echo   git merge upstream/master
echo   git push origin main
echo   cd ..\..
echo   git add %SUBMODULE_PATH%
echo   git commit -m "Bump litegraph submodule"
echo.

endlocal