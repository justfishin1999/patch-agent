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
