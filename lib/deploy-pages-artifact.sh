#!/usr/bin/env bash
set -euo pipefail

die() {
    echo "::error::$*" >&2
    exit 1
}

deployment_action=${deployment_action:?missing deployment_action}
source_dir=${source_dir:-.}
state_branch=${pages_artifact_state_branch:?missing pages_artifact_state_branch}
state_repository=${deployment_repository:?missing deployment_repository}
token=${token:?missing token}
umbrella_path=${umbrella_path:?missing umbrella_path}
preview_file_path=${preview_file_path:-}
preview_number=${preview_number:-}
git_config_name=${git_config_name:-}
git_config_email=${git_config_email:-}
deploy_commit_message=${deploy_commit_message:-}
remove_commit_message=${remove_commit_message:-}
server_url=${GITHUB_SERVER_URL:?missing GITHUB_SERVER_URL}

if [[ "$state_branch" == *$'\n'* || "$state_branch" == *$'\r'* ]] || ! git check-ref-format "refs/heads/$state_branch"; then
    die "Invalid pages-artifact-state-branch: $state_branch"
fi

if [[ "$state_branch" == "${default_branch:-}" ]]; then
    die "pages-artifact-state-branch must not be the repository's default branch."
fi

if [[ -z "$umbrella_path" || "$umbrella_path" == /* || "$umbrella_path" == *$'\n'* || "$umbrella_path" == *$'\r'* ]]; then
    die "umbrella-dir must be a non-empty relative path without newlines."
fi
case "/$umbrella_path/" in
    */../* | */./*) die "umbrella-dir must not contain '.' or '..' path segments." ;;
esac

if [[ "$deployment_action" == "deploy" || "$deployment_action" == "sync" ]]; then
    [[ -d "$source_dir" ]] || die "source-dir does not exist or is not a directory: $source_dir"
    source_dir=$(cd "$source_dir" && pwd -P)
    if find "$source_dir" -type l -print -quit | grep -q .; then
        die "source-dir contains symbolic links. GitHub Pages artifacts dereference links, so remove them before publishing."
    fi
    if ! find "$source_dir" -type f -print -quit | grep -q .; then
        die "source-dir is empty. Provide at least one regular file to publish."
    fi
fi

if [[ "$deployment_action" == "deploy" ]]; then
    [[ "$preview_file_path" == "$umbrella_path"/* ]] || die "Invalid preview path: $preview_file_path"
fi

if [[ "$deployment_action" != "deploy" && "$deployment_action" != "remove" && "$deployment_action" != "sync" ]]; then
    die "Unsupported artifact deployment action: $deployment_action"
fi

if [[ ! "$state_repository" =~ ^[^/]+/[^/]+$ ]]; then
    die "deployment-repository must be in owner/repository form: $state_repository"
fi
if [[ "$state_repository" != "${GITHUB_REPOSITORY:?missing GITHUB_REPOSITORY}" ]]; then
    die "pages-artifact mode deploys to the current repository; set deploy-repository to $GITHUB_REPOSITORY."
fi

work_root=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-preview-pages-artifact.XXXXXX")
artifact_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-preview-pages-artifact-upload.XXXXXX")
trap 'rm -rf "$work_root"' EXIT
state_dir="$work_root/state"
remote_url="${server_url%/}/$state_repository.git"
auth_header="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$token" | base64 | tr -d '\r\n')"

remote_has_branch=false
if git -c "http.extraheader=$auth_header" ls-remote --exit-code --heads "$remote_url" "refs/heads/$state_branch" >/dev/null 2>&1; then
    remote_has_branch=true
fi

if [[ "$remote_has_branch" == true ]]; then
    GIT_TERMINAL_PROMPT=0 git -c "http.extraheader=$auth_header" clone \
        --depth=1 --single-branch --branch "$state_branch" "$remote_url" "$state_dir"
elif [[ "$deployment_action" == "sync" ]]; then
    git init --quiet -b "$state_branch" "$state_dir"
    git -C "$state_dir" remote add origin "$remote_url"
else
    die "State branch '$state_branch' does not exist. Run this action with action: sync on the default branch first to initialize it."
fi

if [[ -n "$(git -C "$state_dir" rev-parse --verify HEAD 2>/dev/null || true)" ]]; then
    old_state_commit=$(git -C "$state_dir" rev-parse HEAD)
else
    old_state_commit=""
fi

state_preview_path="$state_dir/$umbrella_path"
case $deployment_action in
    sync)
        preview_backup="$work_root/previews"
        if [[ -e "$state_preview_path" ]]; then
            mkdir -p "$(dirname "$preview_backup")"
            mv "$state_preview_path" "$preview_backup"
        fi
        rsync -a --delete --exclude='/.git/' "$source_dir/" "$state_dir/"
        rm -rf "$state_preview_path"
        if [[ -e "$preview_backup" ]]; then
            mkdir -p "$(dirname "$state_preview_path")"
            mv "$preview_backup" "$state_preview_path"
        fi
        ;;
    deploy)
        [[ "$preview_number" =~ ^[1-9][0-9]*$ ]] || die "pr-number must be a positive integer in pages-artifact mode."
        target_path="$state_dir/$preview_file_path"
        rm -rf "$target_path"
        mkdir -p "$target_path"
        rsync -a "$source_dir/" "$target_path/"
        ;;
    remove)
        [[ "$preview_number" =~ ^[1-9][0-9]*$ ]] || die "pr-number must be a positive integer in pages-artifact mode."
        rm -rf "$state_dir/$preview_file_path"
        ;;
esac

if find "$state_dir" -path "$state_dir/.git" -prune -o -type l -print -quit | grep -q .; then
    die "The Pages artifact state contains symbolic links. Remove them before publishing."
fi

if ! find "$state_dir" -path "$state_dir/.git" -prune -o -type f -print -quit | grep -q .; then
    die "The Pages artifact is empty. Ensure source-dir contains at least one file."
fi

git -C "$state_dir" config user.name "${git_config_name:-${GITHUB_ACTOR:-github-actions[bot]}}"
git -C "$state_dir" config user.email "${git_config_email:-41898282+github-actions[bot]@users.noreply.github.com}"
git -C "$state_dir" add --all --force
if ! git -C "$state_dir" diff --cached --quiet; then
    case $deployment_action in
        sync) commit_message="feat: sync Pages artifact site" ;;
        deploy) commit_message="${deploy_commit_message:-feat: deploy preview for PR $preview_number}" ;;
        remove) commit_message="${remove_commit_message:-chore: remove preview for PR $preview_number}" ;;
    esac
    git -C "$state_dir" commit --quiet -m "$commit_message"
    if [[ -n "$old_state_commit" ]]; then
        lease="--force-with-lease=refs/heads/$state_branch:$old_state_commit"
    else
        lease="--force-with-lease=refs/heads/$state_branch:"
    fi
    GIT_TERMINAL_PROMPT=0 git -C "$state_dir" -c "http.extraheader=$auth_header" push \
        "$lease" origin "HEAD:refs/heads/$state_branch"
fi

state_commit=$(git -C "$state_dir" rev-parse HEAD)
mkdir -p "$artifact_dir"
rsync -a --delete --exclude='/.git/' "$state_dir/" "$artifact_dir/"

{
    echo "pages_artifact_path=$artifact_dir"
    echo "deployed_commit_sha=$state_commit"
} >> "$GITHUB_ENV"
{
    echo "pages_artifact_path=$artifact_dir"
    echo "deployed_commit_sha=$state_commit"
} >> "$GITHUB_OUTPUT"
