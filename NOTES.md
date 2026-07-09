# Project Documentation

## Project Structure

This project is a FastAPI-based web application with the following structure:

- `main.py` - Main application entry point containing the FastAPI app and route definitions
- `config.yaml` - Configuration file for logging settings
- `requirements.txt` - Python dependencies
- `static/` - Static files directory containing HTML templates
  - `drawflow-editor.html` - HTML template for the drawflow editor interface
  - `drawflow.html` - HTML template for drawflow functionality  
  - `index.html` - Main index page
- `test_drawflow.py` - Test file for drawflow functionality
- `Core/` - Core application modules
  - `app_setup.py` - FastAPI app setup and static file mounting
  - `routes.py` - Route handlers for the web interface
  - `__init__.py` - Package initialization
- `vendor/` - Third-party libraries directory
  - `drawflow/` - Drawflow library
  - `litegraph/` - LiteGraph library

## Module Responsibilities

### main.py
- Defines the FastAPI application instance
- Imports routes to register them with the app
- Runs the uvicorn server on 127.0.0.1:8000

### Core/app_setup.py
- Creates the FastAPI application instance
- Mounts static files for Drawflow and frontend assets
- Sets up the application structure

### Core/routes.py
- Defines route handlers for the web interface
- Handles root endpoint with HTML response
- Serves the drawflow editor interface from the main route

### config.yaml
- Configures logging level (currently set to INFO)
- Provides a foundation for application configuration

### requirements.txt
- Lists all Python dependencies required for the application
- Includes FastAPI framework and related packages
- Contains web server dependencies (uvicorn, uvloop, etc.)
- Includes configuration management (python-dotenv, PyYAML)

### Static Files
- `drawflow-editor.html` - Full-featured drawflow editor interface with node creation and export functionality (served at root)
- `drawflow.html` - Drawflow interface focused on graph execution with run functionality (not currently used in routing)
- `index.html` - Main index page with LiteGraph-based interface (not currently used in routing)

### test_drawflow.py
- Contains testing functions for drawflow functionality
- Includes file and directory checking utilities
- Provides main test execution function

## Design Decisions

1. **FastAPI Framework**: Chosen for its high performance, automatic API documentation generation, and type safety features.

2. **Static File Serving**: HTML templates are served as static files to provide the frontend interface for drawflow functionality.

3. **Configuration Management**: YAML-based configuration allows for easy modification of settings without code changes.

4. **Vendor Libraries**: Third-party libraries (drawflow and litegraph) are included in vendor directory for dependency management.

5. **Logging Configuration**: Basic logging setup with INFO level as default, providing foundation for application monitoring.

6. **Cross-platform Compatibility**: Dependencies include platform-specific optimizations (uvloop for Unix systems).

7. **Modular Architecture**: The application is organized into a Core package to separate concerns and improve maintainability.

8. **Current Routing Focus**: The main route (/) serves the drawflow editor interface, while other HTML files are present but not actively routed to in the current implementation.

## Dependencies Overview

The application uses:
- FastAPI for web framework
- Uvicorn for ASGI server
- PyYAML for configuration parsing
- Python-dotenv for environment variable management
- Various utility libraries for type checking and HTTP handling
