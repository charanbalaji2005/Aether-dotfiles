"""AetherOS assistant: provider abstraction, secret storage, action registry.

The model never executes anything. It may *propose* actions from the fixed
registry (ai/registry.py); the backend validates each proposal against the
live system, and the shell runs it only after the user clicks Run.
"""
