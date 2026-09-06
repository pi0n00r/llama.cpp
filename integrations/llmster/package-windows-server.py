# AI-NOTICE:Schema-Version=0.1
# AI-NOTICE:License=MIT
# AI-NOTICE:Project=llama.cpp-pi0n00r
# AI-NOTICE:Repository=https://github.com/pi0n00r/llama.cpp
"""Package the Windows server's PE closure and ROCm BLAS runtime data."""

import argparse
import hashlib
import json
import os
import shutil
from collections import deque
from pathlib import Path

import pefile


def inspect(path):
    with pefile.PE(str(path), fast_load=True) as pe:
        if pe.FILE_HEADER.Machine != 0x8664:
            raise ValueError(f"Not an x64 PE: {path}")
        pe.parse_data_directories(directories=[1, 13, 0])
        imports = {}
        for table in ("DIRECTORY_ENTRY_IMPORT", "DIRECTORY_ENTRY_DELAY_IMPORT"):
            for entry in getattr(pe, table, []):
                imports.setdefault(entry.dll.decode().lower(), []).extend(
                    item.name.decode() if item.name else f"#{item.ordinal}"
                    for item in entry.imports
                )
        exports = set()
        for item in getattr(getattr(pe, "DIRECTORY_ENTRY_EXPORT", None), "symbols", []):
            exports.add(f"#{item.ordinal}")
            if item.name:
                exports.add(item.name.decode())
        return imports, exports


def file_index(roots):
    result = {}
    for root, recursive in roots:
        paths = root.rglob("*") if recursive else root.iterdir()
        for path in sorted(paths):
            if path.is_file() and path.suffix.lower() in {".dll", ".exe"}:
                result.setdefault(path.name.lower(), path)
    return result


def dependency_closure(index, system):
    pending = deque(["llama-server.exe", "ggml-cpu.dll", "ggml-hip.dll"])
    selected = {}
    external = set()
    while pending:
        name = pending.popleft()
        if name in selected:
            continue
        path = index[name]
        imports, exports = inspect(path)
        selected[name] = (path, imports, exports)
        for dependency in imports:
            if dependency in index:
                pending.append(dependency)
            elif dependency.startswith(("api-ms-win-", "ext-ms-win-")):
                external.add(dependency)
            elif (system / dependency).is_file():
                external.add(dependency)
            else:
                raise ValueError(f"Unresolved dependency: {name} -> {dependency}")
    for name, (_, imports, _) in selected.items():
        for dependency, symbols in imports.items():
            if dependency in selected:
                missing = set(symbols) - selected[dependency][2]
                if missing:
                    raise ValueError(f"Missing exports: {name} -> {dependency}: {sorted(missing)}")
    return selected, sorted(external)


def copy_runtime_data(sdk, output):
    required = (
        Path(".kpack/blas_lib_gfx1151.kpack"),
        Path("bin/rocblas"),
        Path("bin/hipblaslt"),
    )
    copied = []
    for relative in required:
        source = sdk / relative
        if not source.exists():
            raise ValueError(f"Required ROCm runtime data absent: {source}")
        files = [source] if source.is_file() else sorted(source.rglob("*"))
        count = 0
        for path in files:
            if not path.is_file():
                continue
            destination = output / path.relative_to(sdk)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            copied.append(destination.relative_to(output).as_posix())
            count += 1
        if not count:
            raise ValueError(f"Empty runtime data directory: {source}")
    return copied


def copy_licenses(source, sdk, output):
    shutil.copy2(source / "LICENSE", output / "LICENSE.llama.cpp")
    count = 0
    for label, root in (("llama.cpp", source / "vendor"), ("ROCm", sdk / "share/doc")):
        if not root.is_dir():
            raise ValueError(f"Licence source absent: {root}")
        for path in root.rglob("*"):
            if path.is_file() and path.name.upper().startswith(("LICENSE", "NOTICE", "COPYING")):
                destination = output / "licenses" / label / path.relative_to(root)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
                count += 1
    if not count:
        raise ValueError("No third-party licence notices were collected.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("compiled", "sdk", "redist", "source", "output", "evidence"):
        parser.add_argument(f"--{name}", required=True, type=Path)
    args = parser.parse_args()
    if any(args.output.iterdir()):
        raise ValueError("Output must be an empty staging directory.")
    index = file_index(((args.compiled, False), (args.sdk / "bin", False), (args.redist, True)))
    selected, external = dependency_closure(index, Path(os.environ["SystemRoot"]) / "System32")
    if any("libomp140" in name for name in selected | dict.fromkeys(external)):
        raise ValueError("Unexpected development-only OpenMP dependency.")
    binary_dir = args.output / "bin"
    binary_dir.mkdir()
    report = []
    for name, (path, imports, exports) in sorted(selected.items()):
        target = binary_dir / path.name
        shutil.copy2(path, target)
        report.append({"file": path.name, "origin": str(path), "imports": imports,
                       "exports": sorted(exports), "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
    data = copy_runtime_data(args.sdk, args.output)
    copy_licenses(args.source, args.sdk, args.output)
    evidence = {"files": report, "windows_system_dependencies": external, "runtime_data": data,
                "scope": "Static import/export closure; actual GPU and LM Studio acceptance remain pending."}
    (args.evidence / "package-closure.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(f"Packaged {len(selected)} PE files and {len(data)} runtime data files.")


if __name__ == "__main__":
    main()
