#!/bin/bash
# Pre-commit hook to run tests before committing in archer
echo "Running swift test before committing..."
swift test
if [ $? -ne 0 ]; then
    echo "ERROR: swift test failed. Commit aborted."
    exit 1
fi
