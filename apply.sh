#!/usr/bin/env bash

if [ $# != 4 ]
then
    cat <<-EOF
Usage:
pat=... $0 {org_url} {proj_name} {repo_name} {branch}

Examples:
    pat=... $0 https://dev.azure.com/azvse aztest aztest bensl/tmpbuild/1201

EOF
    exit 1
fi

if ! [[ ${pat} ]]
then 
    echo please set pat as your personalAccessToken
    exit 2
fi

export org_url=$1
export proj_name=$2
export repo_name=$3
export branch=$4

function get_repo_id {
  az repos list --org "${org_url}" \
                --proj aztest | \
    jq -r ".[] | select(.name == \"${repo_name}\") | .id"
}
# https://unix.stackexchange.com/a/383166
# export function to subshells for bash
typeset -fx get_repo_id

function print_policy_list() {
  az repos policy list \
    --branch ${branch} \
    --repository-id "${repo_id}" \
    --org "${org_url}" \
    --project "${proj_name}"
}

function setup_build_policy() {
  curl -X POST "${org_url}"/"${proj_name}"/_apis/policy/configurations?api-version=7.2-preview.1 \
      -H "Authorization: Basic "$(echo -n :${pat} | base64) \
      -H 'Content-Type: application/json' \
      -d \
  '{
    "isEnabled": true,
    "isBlocking": false,
    "type": {
      "id": "fa4e907d-c16b-4a4c-9dfa-4906e5d171dd"
    },
    "settings": {
      "allowDownvotes": false,
      "blockLastPusherVote": true,
      "creatorVoteCounts": false,
      "minimumApproverCount": 2,
      "requireVoteOnEachIteration": true,
      "requireVoteOnLastIteration": true,
      "resetOnSourcePush": false,
      "resetRejectionsOnSourcePush": false,
      "scope": [
        {       
          "repositoryId": "'${repo_id}'",
          "refName": "refs/heads/'${branch}'",
          "matchKind": "exact"
        }
      ]
    }
  }'
}

function setup_build_validation() {
  # TODO: get build definition id
  build_definition_id=2
  az repos policy build create \
    --blocking true \
    --branch ${branch} \
    --build-definition-id ${build_definition_id}\
    --display-name "" \
    --enabled true \
    --manual-queue-only false \
    --queue-on-source-update-only true \
    --valid-duration 720 \
    --repository-id ${repo_id} \
    --org ${org_url} \
    --project ${proj_name} \

}

export repo_id=$( get_repo_id )

print_policy_list
setup_build_policy
setup_build_validation
