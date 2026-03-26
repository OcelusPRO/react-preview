#!/bin/sh

echo "🗑️ Clearing all deployment hashes to force a full rebuild..."
find /var/www/html -type f -name "*.hash" -delete
echo "✅ Done! The synchronization script will rebuild all active branches on its next cycle."