#!/usr/bin/env python3
"""Select an available iPhone, preferring an already booted device."""
import json
import subprocess
import sys

try:
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        check=True, capture_output=True, text=True,
    )
    devices = [
        device
        for runtime in json.loads(result.stdout)["devices"].values()
        for device in runtime
        if device.get("isAvailable") and "iPhone" in device["name"]
    ]
    devices.sort(key=lambda device: (
        device["state"] != "Booted",
        device["name"] != "iPhone 17",
        device["name"],
    ))
    if not devices:
        raise ValueError("Install an iPhone simulator runtime in Xcode Settings.")
    print(devices[0]["udid"])
except (subprocess.CalledProcessError, ValueError, KeyError) as error:
    sys.exit(f"Could not select a simulator: {error}")
