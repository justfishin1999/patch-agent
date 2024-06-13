# Install-PatchAgent.ps1
# Run this script with administrative privileges

# Define variables
$installPath = "C:\Program Files\PatchAgent"
$checkOnlyScript = "patch_agent_check_only.py"
$installScript = "patch_agent.py"
$serverIP = "172.22.50.247"

# Create installation directory
if (-Not (Test-Path -Path $installPath)) {
    New-Item -ItemType Directory -Force -Path $installPath
}

# Python script contents
$patchAgentCheckOnlyScriptContent = @"
import os
import requests
import subprocess
from datetime import datetime
import platform

try:
    import wmi
except ImportError:
    if os.name == 'nt':
        subprocess.check_call(["pip", "install", "wmi"])
        import wmi

SERVER_URL = "http://172.22.50.247:5000/api/machines"
MACHINE_NAME = os.environ['COMPUTERNAME']

def get_os_name():
    if os.name == 'nt':
        try:
            c = wmi.WMI()
            os_info = c.Win32_OperatingSystem()[0]
            os_name = os_info.Caption
            print(f"OS Name from WMI: {os_name}")
            return os_name
        except Exception as e:
            print(f"Error retrieving OS name from WMI: {e}")
            return f"{platform.system()} {platform.release()}"
    else:
        try:
            os_name = subprocess.check_output('lsb_release -d', shell=True).decode('utf-8').strip().split(":")[1].strip()
            print(f"OS Name from lsb_release: {os_name}")
            return os_name
        except subprocess.CalledProcessError as e:
            print(f"Error retrieving OS name from lsb_release: {e}")
            return f"{platform.system()} {platform.release()}"

def get_system_specs():
    if os.name == 'nt':
        specs = subprocess.check_output(['systeminfo'], shell=True).decode('utf-8')
    else:
        specs = subprocess.check_output(['uname', '-a'], shell=True).decode('utf-8')
    return specs

def check_updates():
    if os.name == 'nt':
        check_command = ["powershell", "-Command", "Import-Module PSWindowsUpdate; Get-WindowsUpdate"]
    else:
        check_command = 'apt list --upgradable'
    
    check_result = subprocess.run(check_command, shell=True, stdout=subprocess.PIPE)
    updates = check_result.stdout.decode('utf-8')
    updates_available = updates.count('upgradable') if os.name != 'nt' else updates.count('Update')
    
    return updates, updates_available

def get_current_installed_patches():
    response = requests.get(f"{SERVER_URL}/{MACHINE_NAME}")
    if response.status_code == 200:
        machine_data = response.json()
        return machine_data.get('updates_installed', 0)
    return 0

def report_status():
    updates, updates_missing = check_updates()
    system_specs = get_system_specs()
    current_installed_patches = get_current_installed_patches()
    os_name = get_os_name()
    
    machine_data = {
        'name': MACHINE_NAME,
        'os': os_name,
        'last_check': datetime.now().isoformat(),
        'updates_missing': updates_missing,
        'updates_installed': current_installed_patches,
        'missing_patches': updates,
        'specs': system_specs,
        'failed_patches': []
    }
    print(f"Machine Data: {machine_data}")
    response = requests.post(SERVER_URL, json=machine_data)
    print(f"Server response: {response.status_code}, {response.text}")
    return response.status_code == 201

if __name__ == "__main__":
    report_status()
"@

$patchAgentScriptContent = @"
import os
import requests
import subprocess
from datetime import datetime
import platform

try:
    import wmi
except ImportError:
    if os.name == 'nt':
        subprocess.check_call(["pip", "install", "wmi"])
        import wmi

SERVER_URL = "http://172.22.50.247:5000/api/machines"
MACHINE_NAME = os.environ['COMPUTERNAME']

def get_os_name():
    if os.name == 'nt':
        try:
            c = wmi.WMI()
            os_info = c.Win32_OperatingSystem()[0]
            os_name = os_info.Caption
            print(f"OS Name from WMI: {os_name}")
            return os_name
        except Exception as e:
            print(f"Error retrieving OS name from WMI: {e}")
            return f"{platform.system()} {platform.release()}"
    else:
        try:
            os_name = subprocess.check_output('lsb_release -d', shell=True).decode('utf-8').strip().split(":")[1].strip()
            print(f"OS Name from lsb_release: {os_name}")
            return os_name
        except subprocess.CalledProcessError as e:
            print(f"Error retrieving OS name from lsb_release: {e}")
            return f"{platform.system()} {platform.release()}"

def get_system_specs():
    if os.name == 'nt':
        specs = subprocess.check_output(['systeminfo'], shell=True).decode('utf-8')
    else:
        specs = subprocess.check_output(['uname', '-a'], shell=True).decode('utf-8')
    return specs

def check_updates():
    if os.name == 'nt':
        check_command = ["powershell", "-Command", "Import-Module PSWindowsUpdate; Get-WindowsUpdate"]
        install_command = ["powershell", "-Command", "Import-Module PSWindowsUpdate; Install-WindowsUpdate -AcceptAll -AutoReboot"]
    else:
        check_command = 'apt list --upgradable'
        install_command = 'sudo apt-get update && sudo apt-get upgrade -y'
    
    check_result = subprocess.run(check_command, shell=True, stdout=subprocess.PIPE)
    updates = check_result.stdout.decode('utf-8')
    updates_available = updates.count('upgradable') if os.name != 'nt' else updates.count('Update')
    
    failed_patches = []
    if updates_available > 0:
        install_result = subprocess.run(install_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if install_result.returncode != 0:
            failed_patches = install_result.stderr.decode('utf-8').splitlines()
        updates_installed = updates_available if not failed_patches else 0
    else:
        updates_installed = 0
    
    return updates, updates_available, updates_installed, failed_patches

def get_current_installed_patches():
    response = requests.get(f"{SERVER_URL}/{MACHINE_NAME}")
    if response.status_code == 200):
        machine_data = response.json()
        return machine_data.get('updates_installed', 0)
    return 0

def report_status():
    updates, updates_missing, updates_installed, failed_patches = check_updates()
    system_specs = get_system_specs()
    current_installed_patches = get_current_installed_patches()
    total_installed_patches = current_installed_patches + updates_installed
    os_name = get_os_name()
    
    machine_data = {
        'name': MACHINE_NAME,
        'os': os_name,
        'last_check': datetime.now().isoformat(),
        'updates_missing': updates_missing,
        'updates_installed': total_installed_patches,
        'missing_patches': updates,
        'specs': system_specs,
        'failed_patches': failed_patches
    }
    print(f"Machine Data: {machine_data}")
    response = requests.post(SERVER_URL, json=machine_data)
    print(f"Server response: {response.status_code}, {response.text}")
    return response.status_code == 201

if __name__ == "__main__":
    report_status()
"@

# Save Python scripts to the installation directory
Set-Content -Path "$installPath\$checkOnlyScript" -Value $patchAgentCheckOnlyScriptContent
Set-Content -Path "$installPath\$installScript" -Value $patchAgentScriptContent

# Install Python and necessary modules
if (-Not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Output "Python is not installed. Installing Python..."
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.9.7/python-3.9.7-amd64.exe" -OutFile "$env:TEMP\python-3.9.7-amd64.exe"
    Start-Process -FilePath "$env:TEMP\python-3.9.7-amd64.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    Remove-Item -Path "$env:TEMP\python-3.9.7-amd64.exe"
}

# Ensure pip is available and install required packages
python -m ensurepip --upgrade
pip install requests wmi

# Create batch files
$checkOnlyBatchContent = "@echo off`r`npython `"$installPath\$checkOnlyScript`""
$installBatchContent = "@echo off`r`npython `"$installPath\$installScript`""

Set-Content -Path "$installPath\check_only.bat" -Value $checkOnlyBatchContent
Set-Content -Path "$installPath\install_updates.bat" -Value $installBatchContent

# Register scheduled tasks
$checkTrigger = New-ScheduledTaskTrigger -Daily -At (Get-Date).AddMinutes(1).Date.AddHours(1).ToShortTimeString() -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue)
$checkAction = New-ScheduledTaskAction -Execute "$installPath\check_only.bat"
$checkPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$checkTask = New-ScheduledTask -Action $checkAction -Trigger $checkTrigger -Principal $checkPrincipal
Register-ScheduledTask -TaskName "PatchAgentCheckOnly" -InputObject $checkTask -Force

$installTrigger = New-ScheduledTaskTrigger -Daily -At "02:00AM"
$installAction = New-ScheduledTaskAction -Execute "$installPath\install_updates.bat"
$installPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$installTask = New-ScheduledTask -Action $installAction -Trigger $installTrigger -Principal $installPrincipal
Register-ScheduledTask -TaskName "PatchAgentInstallUpdates" -InputObject $installTask -Force

Install-Module -Name PSWindowsUpdate -RequiredVersion 2.2.0.3

Write-Output "PatchAgent installation and setup complete."
