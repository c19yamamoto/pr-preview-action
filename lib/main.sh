#!/usr/bin/env bash
# shellcheck source-path=..

source "$GITHUB_ACTION_PATH/lib/calculate-pages-base-url.sh"
source "$GITHUB_ACTION_PATH/lib/remove-prefix-path.sh"
source "$GITHUB_ACTION_PATH/lib/determine-auto-action.sh"

declare deployment_action deployment_method pr_number deployment_repository pages_base_url pages_base_path umbrella_path action_repository action_ref deprecated_custom_url pages_artifact_state_branch default_branch github_ref

deployment_method=${deployment_method:-branch}
case $deployment_method in
    branch | pages-artifact) ;;
    *)
        echo "::error::deployment-method must be 'branch' or 'pages-artifact'. Got: $deployment_method" >&2
        exit 1
        ;;
esac

if [ "$deployment_action" = "auto" ]; then
    echo >&2 "Determining auto action"
    deployment_action=$(determine_auto_action "$GITHUB_EVENT_NAME" "$GITHUB_EVENT_PATH" "$deployment_method" "${default_branch:-}" "${github_ref:-}")
    echo >&2 "Auto action is $deployment_action"
fi

if [ "$deployment_action" = "sync" ] && [ "$deployment_method" != "pages-artifact" ]; then
    echo "::error::action: sync is only supported with deployment-method: pages-artifact." >&2
    exit 1
fi

if [ "$deployment_method" = "pages-artifact" ]; then
    pages_artifact_state_branch=${pages_artifact_state_branch:-pr-preview-pages-artifact-state}
    if [[ "$pages_artifact_state_branch" == *$'\n'* || "$pages_artifact_state_branch" == *$'\r'* ]] || ! git check-ref-format "refs/heads/$pages_artifact_state_branch"; then
        echo "::error::Invalid pages-artifact-state-branch: $pages_artifact_state_branch" >&2
        exit 1
    fi
fi

if [[ -z "$umbrella_path" || "$umbrella_path" == /* || "$umbrella_path" == *$'\n'* || "$umbrella_path" == *$'\r'* ]]; then
    echo "::error::umbrella-dir must be a non-empty relative path without newlines." >&2
    exit 1
fi
case "/$umbrella_path/" in
    */../* | */./*)
        echo "::error::umbrella-dir must not contain '.' or '..' path segments." >&2
        exit 1
        ;;
esac

if [ -n "$pr_number" ] && ! [[ "$pr_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "::error::pr-number must be a positive integer." >&2
    exit 1
fi
if { [ "$deployment_action" = "deploy" ] || [ "$deployment_action" = "remove" ]; } && [ -z "$pr_number" ]; then
    echo "::error::pr-number is required for deploy and remove actions." >&2
    exit 1
fi

# Deprecation of custom-url in favour of pages-base-url
if [ -z "$pages_base_url" ] && [ -n "$deprecated_custom_url" ]; then
    pages_base_url=$deprecated_custom_url
fi

# If pages_base_url was not set by the user, try to guess
if [ -z "$pages_base_url" ]; then
    pages_base_url=$(calculate_pages_base_url "$deployment_repository")
fi
if [[ "$pages_base_url" == *$'\n'* || "$pages_base_url" == *$'\r'* || "$pages_base_path" == *$'\n'* || "$pages_base_path" == *$'\r'* ]]; then
    echo "::error::pages-base-url and pages-base-path must not contain newlines." >&2
    exit 1
fi

preview_file_path="$umbrella_path/pr-${pr_number:-}"

if [ -n "$pr_number" ]; then
    preview_url_path=$(remove_prefix_path "$pages_base_path" "$preview_file_path")
    preview_url="https://$pages_base_url/$preview_url_path/"
else
    preview_url_path=""
    preview_url="https://$pages_base_url/"
fi
if [ -n "$pr_number" ] && [ -n "$pages_base_path" ] && [ "$(remove_prefix_path "" "$preview_file_path")" = "$preview_url_path" ]; then
    echo "::warning title=pages-base-path doesn't match::The pages-base-path directory ($pages_base_path) does not contain umbrella-dir ($umbrella_path). pages-base-path has been ignored. The value of umbrella-dir should start with the value of pages-base-path."
    preview_url_path=$preview_file_path
    preview_url="https://$pages_base_url/$preview_url_path/"
fi

action_version=$("$GITHUB_ACTION_PATH/lib/find-current-git-tag.sh" -p "$action_repository" -f "$action_ref")
action_start_timestamp=$(date '+%s')
action_start_time=$(date '+%Y-%m-%d %H:%M %Z')

# Export variables for later use by this action
{
    echo "empty_dir_path=$(mktemp -d)"
    echo "deployment_action=$deployment_action"

    echo "preview_file_path=$preview_file_path"
    echo "deployment_method=$deployment_method"
    echo "preview_number=$pr_number"
    echo "default_branch=$default_branch"
    if [ "$deployment_method" = "pages-artifact" ]; then
        echo "pages_artifact_state_branch=$pages_artifact_state_branch"
    fi
    echo "pages_base_url=$pages_base_url"
    echo "preview_url_path=$preview_url_path"
    echo "preview_url=$preview_url"

    echo "action_repository=$action_repository"
    echo "action_version=$action_version"
    echo "action_start_time=$action_start_time"
} >> "$GITHUB_ENV"

# Export variables for use by later actions in user workflow
{
    echo "deployment_action=$deployment_action"
    echo "deployment_method=$deployment_method"

    echo "pages_base_url=$pages_base_url"
    echo "preview_url_path=$preview_url_path"
    echo "preview_url=$preview_url"

    echo "action_version=$action_version"
    echo "action_start_timestamp=$action_start_timestamp"
    echo "action_start_time=$action_start_time"
} >> "$GITHUB_OUTPUT"
