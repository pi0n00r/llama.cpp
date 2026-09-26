# AI-NOTICE:Schema-Version=0.1
# AI-NOTICE:License=MIT
# AI-NOTICE:Project=llama.cpp-pi0n00r
# AI-NOTICE:Repository=https://github.com/pi0n00r/llama.cpp
"""Focused regression checks for the native Windows runtime packager."""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("packager", Path(__file__).with_name("package-windows-server.py"))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class ClosureTests(unittest.TestCase):
    def graph(self):
        return {
            "llama-server.exe": ({"llama.dll": ["serve"]}, set()),
            "ggml-cpu.dll": ({"ggml-base.dll": ["compute"]}, set()),
            "ggml-hip.dll": ({"ggml-base.dll": ["compute"]}, set()),
            "llama.dll": ({"ggml-base.dll": ["compute"]}, {"serve"}),
            "ggml-base.dll": ({"api-ms-win-crt-runtime-l1-1-0.dll": ["malloc"]}, {"compute"}),
        }

    def resolve(self, graph, missing=None):
        index = {name: Path(name) for name in graph if name != missing}
        with tempfile.TemporaryDirectory() as system:
            with patch.object(packager, "inspect", side_effect=lambda path: graph[path.name]):
                return packager.dependency_closure(index, Path(system))

    def test_transitive_closure_includes_dynamic_backends(self):
        selected, external = self.resolve(self.graph())
        self.assertEqual(set(selected), set(self.graph()))
        self.assertEqual(external, ["api-ms-win-crt-runtime-l1-1-0.dll"])

    def test_missing_dll_is_not_success(self):
        with self.assertRaisesRegex(ValueError, "Unresolved dependency"):
            self.resolve(self.graph(), missing="ggml-base.dll")

    def test_present_dll_with_wrong_exports_is_not_success(self):
        graph = self.graph()
        graph["llama.dll"] = ({}, {"wrong_abi"})
        with self.assertRaisesRegex(ValueError, "Missing exports"):
            self.resolve(graph)

    def test_cycle_terminates(self):
        graph = self.graph()
        graph["ggml-base.dll"][0]["llama.dll"] = ["serve"]
        selected, _ = self.resolve(graph)
        self.assertEqual(len(selected), 5)

    def test_missing_gpu_data_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "runtime data absent"):
                packager.copy_runtime_data(Path(directory), Path(directory) / "out")


if __name__ == "__main__":
    unittest.main()
