@echo off
REM SCOUT Deployment Batch File
REM This runs the PowerShell deployment script

powershell -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*