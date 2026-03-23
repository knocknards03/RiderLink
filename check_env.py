import shutil
import os
import sys

def check_tool(name, version_cmd):
    # Attempt to dynamically locate the executable in the system PATH
    path = shutil.which(name)
    print(f"Checking {name}...", end=" ")
    
    if path:
        print(f"FOUND at {path}")
        # Run the tool with its version flag to prove functionality
        os.system(f"{name} {version_cmd}")
    else:
        print("NOT FOUND")
        print(f"  -> Please install {name} or add it to your PATH.")

def main():
    print("--- RiderLink Environment Check ---")
    
    # 1. Require PlatformIO for ESP32 compiling
    check_tool("pio", "--version")
    
    # 2. Require Flutter for the App UI compiling
    check_tool("flutter", "--version")
    
    # 3. Require Git for repository version control
    check_tool("git", "--version")
    
    print("\n--- Project Check ---")
    # Resolve the absolute path of this python file so the script works flawlessly regardless of which folder the user navigates into
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Securely verify that the PlatformIO hardware configuration file is present
    if os.path.exists(os.path.join(script_dir, "firmware", "platformio.ini")):
        print("[OK] firmware/platformio.ini found")
    else:
        print("[ERR] firmware/platformio.ini missing")
        
    # Securely verify that the Flutter App software properties file is present
    if os.path.exists(os.path.join(script_dir, "app", "pubspec.yaml")):
        print("[OK] app/pubspec.yaml found")
    else:
        print("[ERR] app/pubspec.yaml missing")

if __name__ == "__main__":
    main()
