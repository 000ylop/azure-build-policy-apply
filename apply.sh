#!/usr/bin/env bash

show_usage() {
    cat <<-EOF
Usage:
    $0 --org-name {string} --proj-name {string} [--repo-name {string} | --repo-id {string}] [--branch {string}] [--pipeline-name {string} | --build-definition-id {number}]

Examples:
    $0 --org-name azvse --proj-name aztest --repo-name aztest --branch bensl/tmpbuild/1201 --pipeline-name Overlake-Build-PullRequest
    $0 --org-name azvse --proj-name aztest --repo-id a4822210-511f-427f-a36d-26a14c29cc89 --branch bensl/tmpbuild/1201 --build-definition-id 2

EOF
}

get_proj_id() {
    az devops project show \
        --project aztest \
	--query "id" \
	--org https://dev.azure.com/azvse \
	--output tsv
}
typeset -fx get_proj_id

get_repo_id() {
    az repos list \
        --org "${org_url}" \
        --query '[].{name:name, id:id}' \
        --proj "${proj_name}" | \
        jq -r ".[] | select(.name == \"${repo_name}\") | .id"
}
# https://unix.stackexchange.com/a/383166
# export function to subshells for bash
typeset -fx get_repo_id

get_build_definition_id() {
    az pipelines build definition show \
        --name "${pipeline_name}" \
        --org "${org_url}" \
        --proj "${proj_name}" \
        --query 'id'
}
typeset -fx get_build_definition_id

while [[ $# -gt 0 ]]; do
    case "$1" in
        --org-name)
            org_name=$2
            shift 2
            ;;
        --proj-name)
            proj_name=$2
            shift 2
            ;;
        --proj-id)
            proj_id=$2
            shift 2
            ;;
        --repo-name)
            repo_name=$2
            shift 2
            ;;
        --repo-id)
            repo_id=$2
            shift 2
            ;;
        --branch)
            export branch=$2
            shift 2
            ;;
        --pipeline-name)
            pipeline_name=$2
            shift 2
            ;;
        --build-definition-id)
            build_definition_id=$2
            shift 2
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
done

org_url=https://dev.azure.com/$org_name

if [[ ! ${org_name} || ! ${proj_name} || (! ${repo_name} && ! ${repo_id}) || (! ${pipeline_name} && ! ${build_definition_id}) ]]; then
    show_usage
    exit 1
fi

if [[ ! "${pat}" ]]; then
    echo "Please set 'pat' as your personalAccessToken"
    exit 2
fi

if [[ ! "${proj_id}" ]]
then
    proj_id=$(get_proj_id)
fi

if [[ ! ${repo_id} && ${repo_name} ]]; then
    repo_id=$(get_repo_id)
    echo repo_id: ${repo_id}
fi

if [[ ! ${build_definition_id} && ${pipeline_name} ]]; then
    build_definition_id=$(get_build_definition_id)
    echo build_definition_id: ${build_definition_id}
fi

print_policy_list() {
    az repos policy list \
        --branch ${branch} \
        --repository-id "${repo_id}" \
        --org "${org_url}" \
        --project "${proj_name}"
}

user_email="tmp1@recolic.net"
setup_branch_security() {
    GIT_REPO_NAMESPACE=2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87
    az devops security permission update \
	--id $GIT_REPO_NAMESPACE \
	--subject "${user_email}" \
	--token repoV2/${proj_id}/${repo_id}/refs/heads/$(echo "${branch}" | python branch_name_hex.py) \
	--allow-bit 2048 \
	--org ${org_url}
}

setup_build_policy() {
    curl -X POST "${org_url}/${proj_name}/_apis/policy/configurations?api-version=7.2-preview.1" \
        -H "Authorization: Basic $(echo -n :${pat} | base64)" \
        -H 'Content-Type: application/json' \
        -d '
    {
        "isEnabled": true,
        "isBlocking": true,
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

setup_build_validation() {
    az repos policy build create \
        --blocking true \
        --branch ${branch} \
        --build-definition-id ${build_definition_id} \
        --display-name "" \
        --enabled true \
        --manual-queue-only false \
        --queue-on-source-update-only true \
        --valid-duration 720 \
        --repository-id ${repo_id} \
        --org ${org_url} \
        --project ${proj_name}
}

print_policy_list
setup_branch_security
setup_build_policy
setup_build_validation
