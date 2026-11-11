#!/usr/bin/env bash

# Determine deployment action based on GitHub event
# Returns: "deploy", "remove", "sync", or "none"
determine_auto_action() {
    local event_name="${1:?missing event_name}"
    local event_path="${2:?missing event_path}"
    local deployment_method="${3:-branch}"
    local default_branch="${4:-}"
    local github_ref="${5:-}"

    case $event_name in
        "pull_request" | "pull_request_target")
            echo >&2 "event_name is $event_name; proceeding"
            ;;
        "push")
            if [ "$deployment_method" = "pages-artifact" ] && \
                [ -n "$default_branch" ] && \
                [ "$github_ref" = "refs/heads/$default_branch" ]; then
                echo >&2 "Default branch push; syncing the Pages artifact site"
                echo "sync"
            else
                echo >&2 "Push event does not update a Pages artifact site; no action to take"
                echo "none"
            fi
            return 0
            ;;
        *)
            echo >&2 "unknown event $event_name; no action to take"
            echo "none"
            return 0
            ;;
    esac

    local event_type
    event_type=$(jq -r ".action" "$event_path")
    echo >&2 "event_type is $event_type"

    case $event_type in
        "opened" | "reopened" | "synchronize")
            echo "deploy"
            ;;
        "closed")
            echo "remove"
            ;;
        *)
            echo >&2 "unknown event type $event_type; no action to take"
            echo "none"
            ;;
    esac
}
