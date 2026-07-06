#!/usr/bin/env bash
set -e

# ============================================================
#  Blueprint UI project setup script (macOS/Linux)
#  - Initializes git (if needed)
#  - Adds/updates the litegraph.js fork as a submodule
#  - Sets up a Python virtual environment and installs deps
# ============================================================

# --- EDIT THESE TWO VALUES FOR YOUR SETUP ---
FORK_URL="https://github.com/YOUR_USERNAME/litegraph.js.git"
SUBMODULE_PATH="vendor/litegraph"
# ----------------------------------------------

echo
echo "=== Blueprint UI Setup ==="
echo

# 1. Make sure we're in a git repo
if [ ! -d ".git" ]; then
  echo "No git repo found. Initializing one..."
  git init
else
  echo "Git repo already initialized."
fi

# 2. Add the litegraph submodule if it isn't already there
if [ -d "$SUBMODULE_PATH/.git" ] || [ -f "$SUBMODULE_PATH/.git" ]; then
  echo "Submodule already present at $SUBMODULE_PATH, skipping add."
else
  echo "Adding litegraph.js fork as a submodule from $FORK_URL ..."
  git submodule add "$FORK_URL" "$SUBMODULE_PATH"
fi

# 3. Make sure submodule content is checked out
echo "Initializing and updating submodules..."
git submodule update --init --recursive

# 4. Add upstream remote inside the submodule so you can pull updates later
pushd "$SUBMODULE_PATH" > /dev/null
if git remote get-url upstream > /dev/null 2>&1; then
  echo "Upstream remote already configured."
else
  echo "Adding 'upstream' remote (jagenjo/litegraph.js) inside submodule..."
  git remote add upstream https://github.com/jagenjo/litegraph.js.git
fi
popd > /dev/null

# 5. Python virtual environment
if [ ! -d "venv" ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv venv
else
  echo "Virtual environment already exists."
fi

echo "Installing Python dependencies..."
source venv/bin/activate
pip install -r requirements.txt

echo
echo "=== Setup complete ==="
echo
echo "To run the app:"
echo "  source venv/bin/activate"
echo "  uvicorn main:app --reload"
echo
echo "To pull upstream litegraph.js updates into your fork later:"
echo "  cd $SUBMODULE_PATH"
echo "  git fetch upstream"
echo "  git merge upstream/master"
echo "  git push origin main"
echo "  cd -"
echo "  git add $SUBMODULE_PATH"
echo "  git commit -m \"Bump litegraph submodule\""
echo