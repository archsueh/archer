#!/bin/bash
# Pre-commit hook to run tests before committing in archer
echo "Checking Swift Package dependencies resolution..."
swift package resolve
if [ $? -ne 0 ]; then
    echo "ERROR: Swift Package dependencies resolution failed. Commit aborted."
    exit 1
fi

echo "Running swift test before committing..."
swift test
if [ $? -ne 0 ]; then
    echo "ERROR: swift test failed. Commit aborted."
    exit 1
fi

