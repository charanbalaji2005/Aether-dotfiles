"""Allow `python3 -m aether ...` (with lib/ on sys.path) for development."""

import sys

from .cli import main

sys.exit(main(sys.argv[1:]))
