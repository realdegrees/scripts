#!/bin/bash
set -e

if [[ "$1" == "-h" ]]; then
  echo "Usage: runner.sh [REPO_URL]"
  echo "Example: runner.sh https://github.com/owner/repo.git"
  echo "  Omitting the [REPO_URL] will print all running containers."
  echo ""
  echo "Options:"
  echo "  -h    Show this help message"
  echo "  -d    Run in background"
  exit 0
fi

if [ -z "$1" ]; then
  echo "Currently running GitHub runner containers:"
  docker ps --filter "name=github-runner" --format "table {{.ID}}\t{{.Names}}"
  exit 0
fi

REPO_URL=$1
REPO_NAME=$(basename "$REPO_URL" .git) # Extracts the repo name
REPO_OWNER=$(basename "$(dirname "$REPO_URL")")
CONTAINER_NAME=github-runner-$REPO_NAME-$REPO_OWNER
ACCESS_TOKEN=$(pass github/pat)

echo "Spinning up a new runner container.."
echo "Username: $REPO_OWNER"
echo "Repo: $REPO_NAME"

# Check if ACCESS_TOKEN is set
if [ -z "$ACCESS_TOKEN" ]; then
  echo "Unable to retrieve PAT from pass (github/pat)"
  exit 1
else
  echo "PAT: ***"
fi

# Fetch runner token from GitHub API
RUNNER_TOKEN=$(curl -s -X POST -H "Authorization: token $ACCESS_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runners/registration-token" | jq -r .token)

# Export variables for docker-compose
export REPO_URL
export REPO_NAME
export REPO_OWNER
export CONTAINER_NAME
export RUNNER_TOKEN

# Start Docker container for the runner
docker-compose -f ~/docker/github-runner/docker-compose.yml up -d
# Get the container ID and name
CONTAINER_ID=$(docker ps -q -f "name=${CONTAINER_NAME}")

# Echo the container ID and name
echo "Successfully started a new GitHub Runner"
echo "ID: $CONTAINER_ID"
echo "Name: $CONTAINER_NAME"

if [[ "$*" != *"-d"* ]]; then
  docker logs -f $CONTAINER_NAME
fi
