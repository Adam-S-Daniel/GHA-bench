"""Make the project root importable so tests can `import matrix_generator`.

pytest's default ``prepend`` import mode only puts a test file's own package
directory on ``sys.path``. The module under test lives at the project root, so
we add the root explicitly here.
"""

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
