#!/bin/bash

# Set variables for repositories and workflows
REPO_A="cppwfs/toupperish"
REPO_B="cppwfs/toupperish"
WF_PATH_A="release-worker.yml"
WF_PATH_B="release-worker.yml"
BRANCH_A="main"
BRANCH_B="main"


# Function to launch workflow and wait for a workflow to complete
launch_workflow_and_wait() {
    # Represents the repository i.e. spring-cloud/spring-cloud-dataflow
    local WF_REPO=$1
    # Represents the path to the workflow of the yaml i.e. ci.yml
    local WF_PATH=$2
    # Represents the branch to run the workflow i.e. main
    local WF_BRANCH=$3

    # retrieve the workflow id of the workflow yaml file
    WF_ID=$(gh workflow list --repo "$WF_REPO" --json id,name,path,state --jq ".[] | select(.path | endswith(\"/$WF_PATH\")) | .id")
    echo "WF_ID=$WF_ID"
    # Launch the workflow
    gh workflow --repo "$WF_REPO" run "$WF_PATH" $WF_PARAM --ref "$WF_REF"
    # Get its run ID
    RUN_ID=
    while [ "$RUN_ID" = "" ]; do
      set +e
      sleep 5
      RUN_ID=$(gh run --repo "$WF_REPO" list --workflow=$WF_PATH --json status,workflowDatabaseId,headBranch,databaseId --jq ".[] | select(.headBranch == \"$WF_BRANCH\") | select(.workflowDatabaseId == $WF_ID) | {databaseId}" | jq -s '.[0].databaseId')
      set -e
      echo "RUN_ID=$RUN_ID"
    done
    # wait for completion and check every 10s
    gh run --repo "$WF_REPO" watch $RUN_ID -i 10
    # log output
    set -e
    # Run view command to dump the log to the console.
    gh run --repo "$WF_REPO" view $RUN_ID --log --exit-status
    # Run view command to retrieve the conclusion of the execution
    RUN_RESULT=$(gh run --repo "$WF_REPO" view $RUN_ID --exit-status --json conclusion --jq  '.conclusion')
    if [[ $RUN_RESULT = "failure" ]]; then
        echo "$WF_PATH execution has failed"
        exit 1
    fi
}

# Trigger workflow in Repository A
echo "Launching workflow in $REPO_A..."

# Wait for Repository A's workflow to complete
launch_workflow_and_wait $REPO_A $WF_PATH_A $BRANCH_A


# Trigger workflow in Repository B
echo "Launching workflow in $REPO_B..."

# Wait for Repository B's workflow to complete
launch_workflow_and_wait $REPO_B $WF_PATH_B $BRANCH_B

echo "Both workflows completed successfully!"
