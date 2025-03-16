#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 <addition_threshold> [-d <relative_subdirectory_path>]"
    exit 1
}

# Default values
RELATIVE_SUBDIR_PATH=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d)
            RELATIVE_SUBDIR_PATH=$2
            shift 2
            ;;
        *)
            if [[ -z "$ADDITION_THRESHOLD" ]]; then
                ADDITION_THRESHOLD=$1
                shift
            else
                usage
            fi
            ;;
    esac
done

# Validate that the addition threshold is provided and is a positive integer
if [[ -z "$ADDITION_THRESHOLD" ]] || ! [[ "$ADDITION_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$ADDITION_THRESHOLD" -le 0 ]; then
    echo "Error: addition_threshold must be a positive integer."
    usage
fi

# Determine the absolute path of the Git repository's root directory
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

# Check if the command was successful
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Error: This script must be run within a Git repository."
    exit 1
fi

# If no directory is provided, default to the Git root directory
if [[ -z "$RELATIVE_SUBDIR_PATH" ]]; then
    RELATIVE_SUBDIR_PATH="."
fi

# Resolve the absolute path of the specified subdirectory
ABSOLUTE_SUBDIR_PATH="$REPO_ROOT/$RELATIVE_SUBDIR_PATH"

# Check if the subdirectory exists
if [ ! -d "$ABSOLUTE_SUBDIR_PATH" ]; then
    echo "Error: The subdirectory '$RELATIVE_SUBDIR_PATH' does not exist within the repository."
    exit 1
fi

# Navigate to the Git repository's root directory
cd "$REPO_ROOT" || { echo "Error: Unable to access '$REPO_ROOT'."; exit 1; }

# Count commits with additions greater than the specified threshold
COMMIT_COUNT=$(git log --no-merges --numstat --pretty="%H" -- "$RELATIVE_SUBDIR_PATH")
# Initialize an empty array to store the filtered commits
FILTERED_COMMITS=()

# Split the COMMIT_COUNT into commits and process each one
while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9a-f]{40}$ ]]; then
        # If the line is a commit hash, process the previous commit's stats
        if [[ -n "$CURRENT_COMMIT_HASH" ]]; then
            if (( TOTAL_ADDITIONS > ADDITION_THRESHOLD )); then
                COMMIT_MESSAGE=$(git log -1 --format=%s "$CURRENT_COMMIT_HASH")
                FILTERED_COMMITS+=("[+] $TOTAL_ADDITIONS [-] $TOTAL_DELETIONS [hash] ${CURRENT_COMMIT_HASH:0:7} [message] $COMMIT_MESSAGE")
            fi
        fi
        # Start a new commit
        CURRENT_COMMIT_HASH="$line"
        TOTAL_ADDITIONS=0
        TOTAL_DELETIONS=0
    else
        # Parse additions and deletions from the line
        ADDITIONS=$(echo "$line" | awk '{print $1}')
        DELETIONS=$(echo "$line" | awk '{print $2}')
        # Handle cases where additions or deletions are "-"
        [[ "$ADDITIONS" == "-" ]] && ADDITIONS=0
        [[ "$DELETIONS" == "-" ]] && DELETIONS=0
        TOTAL_ADDITIONS=$((TOTAL_ADDITIONS + ADDITIONS))
        TOTAL_DELETIONS=$((TOTAL_DELETIONS + DELETIONS))
    fi
done <<< "$COMMIT_COUNT"

# Process the last commit
if [[ -n "$CURRENT_COMMIT_HASH" && $TOTAL_ADDITIONS -gt ADDITION_THRESHOLD ]]; then
    COMMIT_MESSAGE=$(git log -1 --format=%s "$CURRENT_COMMIT_HASH")
    FILTERED_COMMITS+=("[+] $TOTAL_ADDITIONS [-] $TOTAL_DELETIONS [hash] ${CURRENT_COMMIT_HASH:0:8} [message] $COMMIT_MESSAGE")
fi

# Output the result in a table format
COMMIT_COUNT=${#FILTERED_COMMITS[@]}
echo "Commits with more than $ADDITION_THRESHOLD additions in '$RELATIVE_SUBDIR_PATH': $COMMIT_COUNT"
printf "%-10s %-10s %-10s %-50s\n" "[+]" "[-]" "Hash" "Message"
printf "%-10s %-10s %-10s %-50s\n" "---------" "---------" "----" "--------------------------------------------------"
for commit in "${FILTERED_COMMITS[@]}"; do
    ADDITIONS=$(echo "$commit" | awk '{print $2}')
    DELETIONS=$(echo "$commit" | awk '{print $4}')
    HASH=$(echo "$commit" | awk '{print $6}')
    MESSAGE=$(echo "$commit" | cut -d' ' -f8-)
    printf "%-10s %-10s %-10s %-50s\n" "$ADDITIONS" "$DELETIONS" "$HASH" "$MESSAGE"
done
