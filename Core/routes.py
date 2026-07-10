from pathlib import Path
 
from fastapi.responses import FileResponse
from .app_setup import app
 
# Single source of truth: the actual file on disk.
# Any edits to this file will now show up immediately on refresh —
# no need to touch routes.py again.
STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
INDEX_FILE = STATIC_DIR / "drawflow-editor.html"
 
 
@app.get("/", response_class=FileResponse)
async def read_root():
    return FileResponse(INDEX_FILE)