"""Run isolated UI tests and inject reversible wallet write failures from the host."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--harness", required=True, type=Path)
parser.add_argument("--result", required=True)
parser.add_argument("--log", required=True, type=Path)
args = parser.parse_args()
simulator = "C6BBDAF1-EF03-4F2E-980F-CB8C472367D6"
bundle = "com.vava.pingpong.acceptance.nov13"
command = [
    "xcodebuild", "-project", "Vava.xcodeproj", "-scheme", "Vava", "-configuration", "Debug",
    "-destination", f"platform=iOS Simulator,id={simulator}", "-derivedDataPath", "Build",
    "-resultBundlePath", args.result, "-parallel-testing-enabled", "NO",
    "-only-testing:VavaAcceptance/WalletFeedbackTests", "test",
]
backups = {}

def restore_storage():
    for destination, backup in backups.items():
        if backup.exists():
            if destination.is_dir():
                (destination / "write-blocker").unlink(missing_ok=True)
                destination.rmdir()
            backup.rename(destination)
process = subprocess.Popen(command, cwd=args.harness, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, bufsize=1)
try:
    with args.log.open("w") as log:
        for line in process.stdout:
            log.write(line)
            log.flush()
            marker = "VAVA_WALLET_FIXTURE "
            if marker not in line:
                continue
            action, acknowledgement = line.split(marker, 1)[1].strip().split(" ", 1)
            ack = Path(acknowledgement).resolve()
            device_root = Path.home() / "Library/Developer/CoreSimulator/Devices" / simulator / "data/Containers/Data/Application"
            if not ack.is_relative_to(device_root) or not ack.name.endswith(".wallet-fixture-ack"):
                raise RuntimeError("Refusing an acknowledgement outside the test simulator")
            container = Path(subprocess.check_output(
                ["xcrun", "simctl", "get_app_container", simulator, bundle, "data"], text=True).strip())
            directory = container / "Library/Application Support/LocalStoreKitWallets"
            if action == "BLOCK":
                ledgers = list(directory.glob("*.json"))
                if len(ledgers) != 1 or not ledgers[0].is_file():
                    raise RuntimeError("Expected one isolated test ledger")
                destination = ledgers[0]
                backup = destination.with_suffix(".feedback-backup")
                if backup.exists():
                    raise RuntimeError("Refusing to overwrite a ledger backup")
                backups[destination] = backup
                destination.rename(backup)
                destination.mkdir()
                (destination / "write-blocker").write_text("Temporary test fixture")
            elif action == "RESTORE":
                restore_storage()
            else:
                raise RuntimeError("Unknown fixture action")
            ack.write_text("Ready")
    code = process.wait()
finally:
    restore_storage()
    if process.poll() is None:
        process.terminate()
        process.wait()
raise SystemExit(code)
