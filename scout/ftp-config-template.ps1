# FTP Configuration Template for SCOUT Deployment
# Copy this file to ftp-config.ps1 and fill in your actual credentials.
# IMPORTANT: Never commit ftp-config.ps1 to version control!

# For enhanced security, it is recommended to use a PSCredential object.
# To create one, run the following command in PowerShell and enter your password when prompted:
# $credential = Get-Credential -UserName "your-username"
# You can then use this $credential object in the configuration below.

@{
    FtpServer = "your-ftp-server.com"
    FtpUsername = "your-username"

    # Option 1: Plain text password (less secure, but simple for getting started).
    # The deployment script will automatically convert this to a secure credential.
    FtpPassword = "your-password"

    # Option 2: PSCredential object (more secure).
    # To use this, comment out FtpPassword above and uncomment the line below.
    # Make sure you have created the $credential object as described in the comments above.
    # FtpCredential = $credential

    RemotePath = "/"
}
