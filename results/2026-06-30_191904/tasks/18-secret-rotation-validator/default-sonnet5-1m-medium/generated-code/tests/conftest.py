"""Make the project root importable regardless of the invocation cwd."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
