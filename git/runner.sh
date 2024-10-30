#!/bin/bash
# Enable immediate exit if any command fails
set -e

DOCKER_COMPOSE_FILE="./docker-compose.yml"

# Help function to display usage instructions and available options
show_help() {
  echo "Usage: runner.sh [OPTIONS] [REPO_URL]"
  echo "Example: runner.sh https://github.com/owner/repo.git"
  echo ""
  echo "Options:"
  echo "  -h    Show this help message"
  echo "  -l    List currently running GitHub runner containers"
  echo "  -f    Path to the docker-compose file"
  echo "  -t    GitHub Personal Access Token (PAT)"
}

# Process command line arguments using getopts
while getopts "hldf:t:" opt; do
  case ${opt} in
  h)
    show_help
    exit 0
    ;;
  l)
    echo "Currently running GitHub runner containers:"
    docker ps --filter "name=github-runner" --format "table {{.ID}}\t{{.Names}}"
    exit 0
    ;;
  f)
    DOCKER_COMPOSE_FILE=$OPTARG
    ;;
  t)
    ACCESS_TOKEN=$OPTARG
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    ;;
  esac
done
shift $((OPTIND - 1))
REPO_URL=$1

# Validate repository URL input
if [ -z "$REPO_URL" ]; then
  echo "No repository URL provided."
  show_help
  exit 1
fi

# Authentication token handling - try to get from command line or password store
if [ -z "$ACCESS_TOKEN" ]; then
  echo "No GitHub Access Token provided. Attempting to get token from 'pass github/pat'"
  ACCESS_TOKEN=$(pass github/pat)
fi

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Unable to retrieve access token from pass (github/pat)"
  exit 1
else
  echo "Token: √"
fi

# Extract repository information and set container naming
REPO_NAME=$(basename "$REPO_URL" .git)
REPO_OWNER=$(basename "$(dirname "$REPO_URL")")
CONTAINER_NAME=github-runner-$REPO_NAME-$REPO_OWNER

echo "Spinning up a new runner container.."
echo "Username: $REPO_OWNER"
echo "Repo: $REPO_NAME"
echo "---"

# Generate runner registration token using GitHub API
RUNNER_TOKEN=$(curl -s -X POST -H "Authorization: token $ACCESS_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runners/registration-token" | jq -r .token)

# Set up environment variables for docker-compose
export REPO_URL
export REPO_NAME
export REPO_OWNER
export CONTAINER_NAME
export RUNNER_TOKEN

# Handle docker-compose file and start the container
if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
  echo "Docker-compose file not found at $DOCKER_COMPOSE_FILE. Downloading default file..."
  curl -sL https://raw.githubusercontent.com/realdegrees/scripts/refs/heads/master/git/docker-compose.yml | docker-compose -f - up -d
else
  echo "Starting docker container from $DOCKER_COMPOSE_FILE"
  docker-compose -f "$DOCKER_COMPOSE_FILE" up -d
fi

# Display container information
CONTAINER_ID=$(docker ps -q -f "name=${CONTAINER_NAME}")
echo "---"
echo "Successfully started a new GitHub Runner"
echo "ID: $CONTAINER_ID"
echo "Name: $CONTAINER_NAME"
echo "---"

# Monitor container logs until runner is ready
docker logs -f $CONTAINER_NAME | { while IFS= read -r line; do
  echo "$line"
  if [[ $line =~ "Listening for Jobs" ]]; then
    echo "---"
    echo "√ Runner is connected to GitHub and ready for jobs"
    echo "√ You can terminate the runner at any point using docker"
    pkill -P $$ 2>/dev/null
    break
  fi
done; }
