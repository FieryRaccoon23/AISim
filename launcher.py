"""
launcher.py

Starts the FastAPI backend and automatically opens the Blueprint UI
in your default web browser.

First-time setup (only needs to be done once):
    pip install -r requirements.txt

Then just run:
    python launcher.py
"""

import threading
import time
import webbrowser

import uvicorn

HOST = "127.0.0.1"
PORT = 8000
URL = f"http://{HOST}:{PORT}"


def open_browser():
    # Give uvicorn a moment to actually start listening before we open the tab.
    time.sleep(1.5)
    webbrowser.open(URL)


def main():
    threading.Thread(target=open_browser, daemon=True).start()
    print(f"Starting server at {URL} ...")
    uvicorn.run("main:app", host=HOST, port=PORT, reload=False)


if __name__ == "__main__":
    main()
