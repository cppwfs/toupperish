#!/bin/bash

# Set variables for repositories and workflows


# Function to wait for a workflow to complete
wait_for_workflow_completion() {
    local REPO=$1
    echo  "Sleeping $REPO"
    sleep 10
}

wait_for_workflow_completion "FOO"
wait_for_workflow_completion "BAR"