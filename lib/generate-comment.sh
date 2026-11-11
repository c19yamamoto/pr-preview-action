#!/bin/bash
set -euo pipefail

# Generate comment content for PR preview deployment

action_repository=${1:?missing action_repository}
action_version=${2:?missing action_version}
preview_url=${3:?missing preview_url}
preview_branch=${4:?missing preview_branch}
server_url=${5:?missing server_url}
deploy_repository=${6:?missing deploy_repository}
action_start_time=${7:?missing action_start_time}
deployment_action=${8:?missing deployment_action}
qr_code_provider=${9:-} # falsy qr code provider means no QR code
deployment_method=${10:-branch}

if [ "$qr_code_provider" = "true" ]; then
    # Default to builtin provider
    qr_code_provider="https://qr.rossjrw.com/?color.dark=0d1117&url="
fi
if [ "$qr_code_provider" = "false" ]; then
    qr_code_provider=""
else
    echo >&2 "Using QR code provider: $qr_code_provider<URL>"
fi

if [ "$deployment_action" = "deploy" ]; then
    qr_code=""
    if [ -n "$qr_code_provider" ]; then
        qr_code="<img src=\"${qr_code_provider}${preview_url}\" height=\"100\" align=\"right\" alt=\"QR code for preview link\">"
    fi

    if [ "$deployment_method" = "pages-artifact" ]; then
        deployment_description="Published with the GitHub Pages Actions artifact at ${action_start_time}. <br>"
    else
        deployment_description="Built to branch [\`${preview_branch}\`](${server_url}/${deploy_repository}/tree/${preview_branch}) at ${action_start_time}. <br>"
    fi

    cat << EOF
[PR Preview Action](https://github.com/${action_repository}) ${action_version}
:---:
| <p>$qr_code</p> :rocket: View preview at <br> ${preview_url} <br><br>
| <h6>${deployment_description}Preview is available after the [GitHub Pages deployment](${server_url}/${deploy_repository}/deployments) completes. <br><br> </h6>
EOF

elif [ "$deployment_action" = "remove" ]; then
    cat << EOF
[PR Preview Action](https://github.com/${action_repository}) ${action_version}
:---:
Preview removed because the pull request was closed.
${action_start_time}
EOF
fi
