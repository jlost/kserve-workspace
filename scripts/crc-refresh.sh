#!/bin/sh
set -eu

sudo echo "Authenticated!"
crc stop || true
echo "y" | crc delete || true
crc cleanup
crc setup
crc start
oc login -u kubeadmin -p ch0nker https://api.crc.testing:6443
./pull_secret.sh
sudo ~/p/rosa/mem-cleanup.sh &
echo "Running mem-cleanup in background."
echo "Ready!"
