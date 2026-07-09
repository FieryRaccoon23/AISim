# Import FastAPI and StaticFiles to set up the application
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

# Create the app instance
app = FastAPI()

# Mount static files for Drawflow and our own frontend assets
app.mount("/vendor/drawflow", StaticFiles(directory="vendor/drawflow/dist"), name="drawflow")
app.mount("/static", StaticFiles(directory="static"), name="static")