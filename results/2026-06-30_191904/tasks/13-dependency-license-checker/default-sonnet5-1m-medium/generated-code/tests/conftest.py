import os
import sys

# Make the project root (parent of tests/) importable so `import manifest_parser`
# etc. work regardless of where pytest is invoked from.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
