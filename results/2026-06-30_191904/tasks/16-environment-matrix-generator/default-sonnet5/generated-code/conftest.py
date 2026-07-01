"""Make the project root importable regardless of pytest's rootdir discovery
(this workspace lives nested inside a larger repo that has its own
pyproject.toml pytest config)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
