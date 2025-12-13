#!/bin/bash

KIND="${1:-deployments}"
NAMESPACE="${2:-kserve-ci-e2e-test}"

kubectl get "$KIND" -n "$NAMESPACE" -w -o json | jq --unbuffered -c '
  if .type then
    {name: .object.metadata.name, type: .type, status: .object.status}
  elif .items then
    .items[] | {name: .metadata.name, status: .status}
  else
    {name: .metadata.name, status: .status}
  end
' | while IFS= read -r json_obj; do
  if [ -n "$json_obj" ]; then
    event_type=$(echo "$json_obj" | jq -r '.type // "INITIAL"')
    name=$(echo "$json_obj" | jq -r '.name')
    if [ -n "$event_type" ] && [ "$event_type" != "null" ]; then
      echo "[$event_type] $name:"
    else
      echo "$name:"
    fi
    echo "$json_obj" | jq '.status'
    echo ""
  fi
done
