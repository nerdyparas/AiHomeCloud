#!/bin/bash
#
# AiHomeCloud Backend Test Runner
#
# Convenience script to run backend tests with verbose output and short tracebacks.
# Usage:
#   ./backend/run_tests.sh          # Run all tests
#   ./backend/run_tests.sh test_auth.py  # Run specific test file
#
# Environment:
#   PYTHONPATH: Set to . (current backend directory)
#   CUBIE_DATA_DIR: Temporary directory for test data
#   CUBIE_NAS_ROOT: Temporary directory for test NAS root
#

set -e

cd "$(dirname "$0")"

echo "Running AiHomeCloud backend tests..."
echo ""

# Run pytest with verbose output and short tracebacks
pytest tests/ -v --tb=short "$@"

echo ""
echo "✓ All tests passed!"
