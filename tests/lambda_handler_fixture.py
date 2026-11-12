"""Load Lambda code without requiring deployment or Python package installation."""
import importlib.util
from pathlib import Path


def load_handler():
    path = Path(__file__).resolve().parents[1] / "lambda" / "log_processor.py"
    spec = importlib.util.spec_from_file_location("log_processor", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.lambda_handler
