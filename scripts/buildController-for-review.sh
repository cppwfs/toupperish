#!/bin/bash

# if no arguments provided provide instructions
if [[ "$#" == 0 ]]; then
  echo "This Script will execute the specified group of workflows passed in via command line args"
  echo "A workflow is specified in a comma delimited format as follows: REPOSITORY,BRANCH,NAME_OF_THE_WORKFLOW_YAML_FILE"
  echo "For example if I wanted to run a workflow in the main branch of the SCDF-UI project it would look like:"
  echo "./workflow_runner.sh spring-cloud/spring-cloud-dataflow-ui,main,foo.yml"
  echo ""
  echo "You can run multiple workflows by enumerating workflow group separated by a blank for example:"
  echo "./workflow_runner.sh spring-cloud/spring-cloud-dataflow-ui,main,foo.yml spring-cloud/spring-cloud-dataflow-ui,main,bar.yml"
  exit 0
fi

workflow=()
# Function to extract each item from comma delimited list
# Parameter comma delimited list of workflow args
process_comma_delimited_list() {
  local element="$1"
  workflow+=("$element")
}


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

#### MAIN Script
# Loop over all command line arguments to obtain workflow information
for arg in "$@"; do
  # Set IFS to comma to split comma-delimited lists to obtain workflow information
  IFS=',' read -ra elements <<< "$arg"

  # Iterate over each element in the current comma-separated list
  for element in "${elements[@]}"; do
    process_comma_delimited_list "$element"
  done
    arraySize=${#workflow[@]}
    if [[ $arraySize -ne 3 ]]; then
      echo "Failed Execution: Expected workflow description to have 3 fields but had $arraySize"
      exit 1
    fi

    repository=${workflow[0]}
    branch=${workflow[1]}
    workflow_path=${workflow[2]}

    echo "Launching workflow $workflow_path for repository $repository for branch $branch"
    launch_workflow_and_wait "$repository" "$workflow_path" "$branch"

    workflow=()
done
