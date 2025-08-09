#!/bin/bash

# Get commit message
COMMIT_MSG=$(git log -1 --pretty=%B)

# Extract version
VERSION=$(echo "$COMMIT_MSG" | grep -Eo '[0-9]{4}\.[0-9]{4}' | head -1 || true)

if [ ! -z "$VERSION" ]; then
    echo "version=$VERSION"
    echo "has_version=true"
else
    echo "has_version=false"
fi
