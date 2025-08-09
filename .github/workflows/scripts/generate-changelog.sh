#!/bin/bash

VERSION="$1"
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
COMMITS=$(git log ${LAST_TAG:+${LAST_TAG}..}HEAD --pretty=format:"%h: %s" --reverse)

# Create changelog directory
mkdir -p /tmp/artifacts/changelog

# Generate changelog header
echo "# NipaPlay $VERSION 更新日志" > /tmp/artifacts/changelog/changelog.md

# Call AI to generate changelog
curl -X POST https://ffmpeg.dfsteve.top/ffmpeg.php \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"gpt-5\",\"temperature\":0.5,\"messages\":[{\"role\":\"user\",\"content\":\"请将以下Git提交记录整理成优雅的中文Markdown更新日志：$COMMITS\"}]}" >> /tmp/artifacts/changelog/changelog.md
