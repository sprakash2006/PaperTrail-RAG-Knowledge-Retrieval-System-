# Starts the PaperTrail FastAPI backend reliably.
# Run from anywhere:  .\start_backend.ps1
# $PSScriptRoot is this file's folder (the project root), so the
# working directory is always correct regardless of where you launch it.

Set-Location "$PSScriptRoot\backend"
& "$PSScriptRoot\venv\Scripts\python.exe" -m uvicorn main:app --port 8000
