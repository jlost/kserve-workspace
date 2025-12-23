#!/bin/bash

kubectl scale deployment opendatahub-operator-controller-manager -n openshift-operators --replicas=0