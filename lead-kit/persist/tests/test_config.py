import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "config.py"

class ConfigTests(unittest.TestCase):
    def test_config_and_environment_precedence(self):
        spec = importlib.util.spec_from_file_location("persist_config", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "persist.env"
            config.write_text('PERSIST_STORE="/configured store"\nPERSIST_PORT=2222\n')
            with patch.dict(os.environ, {"PERSIST_CONFIG": str(config), "PERSIST_STORE": "/override"}, clear=True):
                values = module.load()
            self.assertEqual(values["PERSIST_STORE"], "/override")
            self.assertEqual(values["PERSIST_PORT"], "2222")

    def test_store_required(self):
        spec = importlib.util.spec_from_file_location("persist_config", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with patch.dict(os.environ, {"PERSIST_CONFIG": "/nonexistent"}, clear=True):
            with self.assertRaises(ValueError):
                module.load()
