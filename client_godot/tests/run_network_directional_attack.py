"""Run the actor/observer directional-attack test against a local test server."""
import argparse
import os
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    args.output_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.setdefault("MIR2X_WORLD_RES", str(project / "build/world_res"))
    env.setdefault("MIR2X_TEXTURE_RES", str(project.parent / "build/Release/res/texture"))
    env.setdefault("MIR2X_AUDIO_RES", str(project / "build/audio"))
    command = [args.godot, "--headless", "--max-fps", "60", "--path", str(project),
               "res://tests/network_directional_attack_smoke.tscn"]
    children = []
    try:
        for role in ("observer", "actor"):
            process = subprocess.Popen(command, env={**env, "MIR2X_DIRECTIONAL_ROLE": role},
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            children.append((role, process))
            if role == "observer":
                time.sleep(0.5)
        passed = True
        for role, process in reversed(children):
            output, _ = process.communicate(timeout=22)
            (args.output_dir / f"{role}.log").write_text(output, encoding="utf-8")
            print(output, end="")
            passed &= process.returncode == 0 and f"DIRECTIONAL ATTACK {role.upper()} PASS" in output
        return 0 if passed else 1
    finally:
        for _, process in children:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
