# Cursor Helper Script for macOS

## Introduction

This script is designed specifically for **macOS** systems and is compatible with **Cursor** versions **0.44.11** or earlier. The script helps back up and update the configuration file, stop any running Cursor processes, and ensure the security of the configuration file.

**Note:** This script is intended for **Cursor version 0.44.11 or earlier**. It may not be compatible with or suitable for later versions.

## Installation and Usage Instructions

### 1. Prerequisites

Ensure you have **Cursor** installed, and it is version **0.44.11 or earlier**. If you have not installed Cursor yet, download and install it from the official source and register an account.

### 2. Running the Script

1. **Download the Script**: Save this script as `cursor_helper.sh`.
2. **Grant Execute Permissions**:
   Navigate to the directory where the script is saved and grant execute permissions using the following command:
   ```bash
   chmod +x cursor_helper.sh
Execute the Script: Run the script with administrator privileges:


sudo ./cursor_helper.sh
During the execution, the script will prompt you to select a language and perform the following tasks:

Check and stop any running Cursor processes.

Back up the current storage.json configuration file.

Update configuration details (such as device IDs).

Display the current directory structure of the configuration file.

3. Post-Script Actions

Re-login to Your Account: After the script has completed, please log out and log back into your Cursor account.

Delete Previous Accounts: If you have previous accounts, go to Cursor and delete them. Make sure to delete all accounts before proceeding. Afterward, you can re-register with your original email or a new one.

Troubleshooting

If you encounter issues with missing configuration files or permissions, ensure that the correct file paths are set and that you have the necessary read/write access.

If the script does not work as expected, make sure you are using Cursor version 0.44.11 or earlier.
