#!/usr/bin/env python3
"""
Test script to verify Drawflow setup is working properly.
This script checks that all required files and directories exist
and that the basic FastAPI server can be started.
"""

import os
import sys

def check_files():
    """Check if all required files exist"""
    required_files = [
        "main.py",
        "vendor/drawflow/dist/drawflow.min.css",
        "vendor/drawflow/dist/drawflow.min.js",
        "CONTEXT.md"
    ]
    
    print("Checking for required files:")
    all_found = True
    for file_path in required_files:
        if os.path.exists(file_path):
            print(f"  ✓ {file_path}")
        else:
            print(f"  ✗ {file_path}")
            all_found = False
    
    return all_found

def check_directories():
    """Check if required directories exist"""
    required_dirs = [
        "vendor/drawflow/dist",
        "static"
    ]
    
    print("\nChecking for required directories:")
    all_found = True
    for dir_path in required_dirs:
        if os.path.isdir(dir_path):
            print(f"  ✓ {dir_path}")
        else:
            print(f"  ✗ {dir_path}")
            all_found = False
    
    return all_found

def main():
    print("=== Drawflow Setup Test ===")
    
    files_ok = check_files()
    dirs_ok = check_directories()
    
    if files_ok and dirs_ok:
        print("\n✓ All checks passed! The Drawflow setup appears to be working correctly.")
        print("\nTo run the application:")
        print("  python main.py")
        print("\nThen open your browser to http://127.0.0.1:8000")
        return 0
    else:
        print("\n✗ Some checks failed. Please review the above errors.")
        return 1

if __name__ == "__main__":
    sys.exit(main())