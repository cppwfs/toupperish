#!/bin/bash

# if no arguments provided provide instructions
if [[ "$#" == 0 ]]; then
  echo "Executes one or workflows in serial fail-fast fashion."
  echo ""
  echo "usage: ./run-workflow.sh [workflow-tuple]*"
  echo "    where [workflow-tuple] is a csv string of workflow coordinates in the form"
  echo '    "repo,branch,workflow" (e.g. "my-repo,main,my-pr.yml")'
  exit 0
fi

# Function to launch workflow and wait for a workflow to complete
# Parameter 1 is the workflow repository
# Parameter 2 is the name of the workflow yaml file
# Parameter 3 is the Branch
launch_workflow_and_wait() {
    # Represents the repository i.e. spring-cloud/spring-cloud-dataflow
    local WF_REPO=$1
    # Represents the path to the workflow of the yaml i.e. ci.yml
    local WF_PATH=$2
    # Represents the branch to run the workflow i.e. main
    local WF_BRANCH=$3

    # retrieve the workflow id of the workflow yaml file
    WF_ID=$(gh workflow list --repo "$WF_REPO" --json id,name,path,state --jq ".[] | select(.path | endswith(\"/$WF_PATH\")) | .id")
    if [ -z "${WF_ID}" ]; then
      echo "No workflow id is associated with the workflow $WF_PATH for the repository $WF_REPO and branch $WF_BRANCH"
      exit 1
    fi
    echo "WF_ID=$WF_ID"
    # Launch the workflow
    gh workflow --repo "$WF_REPO" run "$WF_PATH" $WF_PARAM --ref "$WF_REF"
    # Get its run ID
    waitTime=0
    RUN_ID=
    while [ "$RUN_ID" = "" ] && [ $waitTime -lt 25 ]; do
      set +e
      sleep 5
      waitTime=$waitTime+5;
      RUN_ID=$(gh run --repo "$WF_REPO" list --workflow=$WF_PATH --json status,workflowDatabaseId,headBranch,databaseId --jq ".[] | select(.headBranch == \"$WF_BRANCH\") | select(.workflowDatabaseId == $WF_ID) | {databaseId}" | jq -s '.[0].databaseId')
      set -e
      echo "RUN_ID=$RUN_ID"
    done

    if [ -z "${RUN_ID}" ]; then
      echo "No RUN_ID id was created for the workflow $WF_PATH for the repository $WF_REPO and branch $WF_BRANCH"
      exit 1
    fi
    # wait for completion and check every 10s
    gh run --repo "$WF_REPO" watch $RUN_ID -i 10
    # log output
    set -e
    gh run --repo "$WF_REPO" view $RUN_ID --log --exit-status
    RUN_RESULT=$(gh run --repo "$WF_REPO" view $RUN_ID --exit-status --json conclusion --jq  '.conclusion')
    if [[ $RUN_RESULT = "failure" ]]; then
        echo "$WF_PATH execution has failed"
        exit 1
    fi
}


# Function to extract a workflow input tuple into 3 elements in the output variable workflowInputTuple
# Parameter The command line arguments
process_workflow_input_tuple() {
  workflowInputTuple=()
  # Set IFS to comma to split comma-delimited lists to obtain workflow information
  IFS=',' read -ra elements <<< "$1"
  # Iterate over each element in the current comma-separated list
  for element in "${elements[@]}"; do
   workflowInputTuple+=("$element")
  done
  arraySize=${#workflowInputTuple[@]}
  if [[ $arraySize -ne 3 ]]; then
    echo "Failed Execution: Expected workflow description to have 3 fields but had $arraySize"
    exit 1
  fi
  repository=${workflowInputTuple[0]}
  branch=${workflowInputTuple[1]}
  workflow_path=${workflowInputTuple[2]}
  workflowInputTuple=()
}

#### MAIN Script
# Loop over all command line arguments to obtain workflow information
for arg in "$@"; do

  process_workflow_input_tuple "$arg"
  echo "Launching workflow $workflow_path for repository $repository for branch $branch"
  launch_workflow_and_wait "$repository" "$workflow_path" "$branch"

done
