# SCOUT Deployment

This directory contains scripts to build and deploy the SCOUT Flutter web app to an FTP server.

## ⚠️ Security Notice

**Never commit `ftp-config.ps1` to version control!** It contains sensitive FTP credentials.

The file `ftp-config-template.ps1` is safe to commit and shows the required structure.

## Setup

Choose one of the following configuration methods:

### Option 1: PowerShell Config File (Recommended)

1. **Copy the template**:
   ```bash
   cp ftp-config-template.ps1 ftp-config.ps1
   ```

2. **Edit `ftp-config.ps1`** with your actual FTP server details:
   ```powershell
   @{
       FtpServer = "your-actual-server.com"
       FtpUsername = "your-actual-username"
       FtpPassword = "your-actual-password"
       RemotePath = "/"
   }
   ```

### Option 2: Environment Variables (.env file)

1. **Copy the template**:
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env`** with your actual FTP server details:
   ```bash
   FTP_SERVER=your-actual-server.com
   FTP_USERNAME=your-actual-username
   FTP_PASSWORD=your-actual-password
   FTP_REMOTE_PATH=/
   ```

## Security Notes

- **`ftp-config.ps1` and `.env` are automatically ignored** by `.gitignore`
- **Never commit these files** to version control
- The deployment script validates that you're not using placeholder credentials
- Both configuration methods are equally secure

2. **Run Deployment**: Use one of these methods:

   **Option A: PowerShell Script (Recommended)**
   ```bash
   .\deploy.ps1
   ```

   **Option B: Batch File**
   ```bash
   .\deploy.bat
   ```

   **Option C: Manual Parameters**
   ```bash
   .\deploy.ps1 -FtpServer "myserver.com" -FtpUsername "user" -FtpPassword "pass"
   ```

## Command Line Options

- `-FtpServer`: FTP server hostname
- `-FtpUsername`: FTP username
- `-FtpPassword`: FTP password
- `-RemotePath`: Remote directory path (default: "/")
- `-SkipBuild`: Skip the Flutter build step
- `-SkipUpload`: Skip the FTP upload step

## Examples

```bash
# Full deployment with config file
.\deploy.ps1

# Build only, no upload
.\deploy.ps1 -SkipUpload

# Upload only, no build
.\deploy.ps1 -SkipBuild

# Custom FTP settings
.\deploy.ps1 -FtpServer "ftp.example.com" -FtpUsername "admin" -FtpPassword "secret123"
```

## Integration with Build Process

You can integrate this into your development workflow by:

1. **Adding to VS Code Tasks**: Create a `.vscode/tasks.json`:
   ```json
   {
     "version": "2.0.0",
     "tasks": [
       {
         "label": "Deploy to FTP",
         "type": "shell",
         "command": "powershell",
         "args": ["-ExecutionPolicy", "Bypass", "-File", "./deploy.ps1"],
         "group": "build"
       }
     ]
   }
   ```

2. **Adding to package.json** (if you add Node.js to your project):
   ```json
   {
     "scripts": {
       "deploy": "powershell -ExecutionPolicy Bypass -File ./deploy.ps1"
     }
   }
   ```

3. **Creating a Flutter alias**: Add to your shell profile:
   ```bash
   alias scout-deploy='cd /path/to/scout && ./deploy.ps1'
   ```