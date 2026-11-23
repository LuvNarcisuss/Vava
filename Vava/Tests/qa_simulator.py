"""Resolve the available iPhone assigned to Vava simulator runs."""
import json
import subprocess

NAME = "Vava QA"


def simulator_id():
    inventory = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True
    )
    matches = [
        device for runtime, devices in json.loads(inventory)["devices"].items()
        if ".iOS-" in runtime
        for device in devices if device["name"] == NAME
    ]
    if len(matches) != 1:
        raise SystemExit(f"Expected one available {NAME} simulator, found {len(matches)}.")
    device = matches[0]
    if device["deviceTypeIdentifier"] != "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro":
        raise SystemExit(f"{NAME} must use the iPhone 17 Pro device type.")
    return device["udid"]


if __name__ == "__main__":
    print(simulator_id())
