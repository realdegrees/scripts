#!/bin/bash
# Enable immediate exit if any command fails
set -e

# Help function to display usage instructions and available options
show_help() {
  echo "Usage: runner.sh [OPTIONS] [REPO_URL]"
  echo "Example: runner.sh https://github.com/owner/repo.git"
  echo ""
  echo "Flags:"
  echo "  -h      Show this help message"
  echo "  -l      List currently running GitHub runner containers"
  echo "  -f      Path to the docker-compose file"
  echo "  -t      GitHub Personal Access Token (PAT)"
  echo "  -v      Enable verbose mode (prints docker-compose output)"
  echo ""
  echo "Commands:"
  echo "  stop    Prints a list of running GitHub runner containers and stops the selected one"
  echo "    -f REPO  Stop all runners matching this filter"
}

stop_runners() {
  local filter=$1
  local containers=$(docker ps -q --filter "name=^github-runner.*$filter.*$")
  if [ -z "$containers" ]; then
    echo "No matching runners found"
    exit 0
  fi

  echo "Stopping runners:"
  printf "%-15s %-18s %-30s %-10s\n" "CONTAINER ID" "OWNER" "REPO" "STATUS"
  for container in $containers; do
    name=$(docker inspect --format '{{.Name}}' $container | sed 's/^\/\(.*\)$/\1/')
    repo=$(echo "$name" | sed 's/github-runner-\(.*\)-[^-]*$/\1/')
    owner=$(echo "$name" | sed 's/.*-\([^-]*\)$/\1/')
    if [ ${#repo} -gt 18 ]; then
      repo="${repo:0:16}.."
    fi
    if docker stop $container >/dev/null 2>&1; then
      status="✓"
    else
      status="✗"
    fi
    printf "%-15s %-18s %-30s %-10s\n" "$container" "$owner" "$repo" "$status"
  done
}

# Process command line arguments using getopts
if [ "$1" = "stop" ]; then
  shift
  if [ $# -eq 0 ]; then
    containers=$(docker ps --filter "name=github-runner" --format "{{.ID}}\t{{.Names}}")
    if [ -z "$containers" ]; then
      echo "No running GitHub runner containers found."
      exit 0
    fi

    container_map=()
    printf "%-5s %-15s %-18s %-30s\n" "INDEX" "CONTAINER ID" "OWNER" "REPO"
    index=1
    while IFS=$'\t' read -r id name; do
      # Extract repo and owner from container name
      repo=$(echo "$name" | sed 's/github-runner-\(.*\)-[^-]*$/\1/')
      owner=$(echo "$name" | sed 's/.*-\([^-]*\)$/\1/')
      if [ ${#repo} -gt 18 ]; then
        repo="${repo:0:16}.."
      fi
      printf "%-5s %-15s %-18s %-30s\n" "$index" "$id" "$owner" "$repo"
      container_map+=("$id")
      index=$((index + 1))
    done <<< "$containers"

    echo ""
    echo "Enter the index of the runner you want to stop:"
    while true; do
      read -r selected_index

      if [[ "$selected_index" =~ ^[0-9]+$ ]] && [ "$selected_index" -gt 0 ] && [ "$selected_index" -le "${#container_map[@]}" ]; then
        break
      else
        echo "Invalid input. Please enter an index from the table."
      fi
    done

    container_id=${container_map[$((selected_index - 1))]}

    if [ -z "$container_id" ]; then
      echo "No container found with the given index."
      exit 1
    fi

    echo "Stopping runner with container ID: $container_id"
    docker stop "$container_id"
    exit 0
  fi
  
  while getopts "f:" opt; do
    case ${opt} in
    f)
      stop_runners $OPTARG
      exit 0
      ;;
    \?)
      echo "Invalid option: $OPTARG" >&2
      exit 1
      ;;
    esac
  done
fi

while getopts "hldf:t:" opt; do
  case ${opt} in
  h)
    show_help
    exit 0
    ;;
  l)
    # This script lists all currently running GitHub runner containers.
    # It displays the container ID, repo owner, and repo name in a formatted table.
    # The output is sorted by the owner column.
    echo "Currently running GitHub runner containers:"
    printf "%-15s %-18s %-30s\n" "CONTAINER ID" "OWNER" "REPO"
    docker ps --filter "name=github-runner" --format "{{.ID}}\t{{.Names}}" | while read -r line; do
      id=$(echo "$line" | cut -f1)
      name=$(echo "$line" | cut -f2)
      # Extract repo and owner from container name
      repo=$(echo "$name" | sed 's/github-runner-\(.*\)-[^-]*$/\1/')
      owner=$(echo "$name" | sed 's/.*-\([^-]*\)$/\1/')
      if [ ${#repo} -gt 18 ]; then
        repo="${repo:0:16}.."
      fi
      printf "%-15s %-18s %-30s\n" "$id" "$owner" "$repo"
    done | sort -k2,2
    exit 0
    ;;
  f)
    DOCKER_COMPOSE_FILE=$OPTARG
    ;;
  t)
    ACCESS_TOKEN=$OPTARG
    ;;
  v)
    VERBOSE=true
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

# Validate if the provided URL is a valid GitHub repository link
if ! [[ "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+$ ]]; then
  echo "Invalid GitHub repository URL. Please provide a valid URL."
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
echo "Owner: $REPO_OWNER"
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

if ! command -v docker-compose &> /dev/null; then
  echo "docker-compose could not be found. Please install it first."
  exit 1
fi

start_docker_compose() {
  if [ -z "$VERBOSE" ]; then
    "$@" >/dev/null 2>&1
  else
    "$@"
  fi
}

# Handle docker-compose file and start the container
if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
  DOCKER_COMPOSE_FILE=$(mktemp -t runner-compose.XXXXXX) >/dev/null 2>&1
  trap 'rm -f "$DOCKER_COMPOSE_FILE"' EXIT
  curl -sL https://raw.githubusercontent.com/realdegrees/scripts/refs/heads/master/git/docker-compose.yml -o "$DOCKER_COMPOSE_FILE"
fi

if ! start_docker_compose docker-compose -f "$DOCKER_COMPOSE_FILE" up -d; then
  echo "Failed to start start container"
  exit 1
fi

# Display container information
CONTAINER_ID=$(docker ps -q -f "name=${CONTAINER_NAME}")
echo "Successfully started container"
echo "ID: $CONTAINER_ID"
echo "Name: $CONTAINER_NAME"
echo "---"

# Monitor container logs until runner is ready
success=false
timeout=10
spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
end=$((SECONDS+timeout))
i=0
# This script continuously checks if a Docker container's logs contain the phrase "Listening for Jobs".
# The script will exit the loop and print a success message once the runner is connected and ready for jobs.
while [ $SECONDS -lt $end ]; do
  if docker logs $CONTAINER_NAME 2>&1 | grep -q "Listening for Jobs"; then
    echo -e "\r√ Runner is connected to GitHub and ready for jobs"
    success=true
    break
  fi
  printf "\r${spinner[i]} Waiting for runner"
  i=$(( (i+1) % ${#spinner[@]} ))
  sleep .1
done

if [ "$success" = true ]; then
  exit 0
else
  echo -e "\r× Runner failed to start within $timeout seconds"
  docker stop "$CONTAINER_ID" >/dev/null 2>&1
  exit 1
fi
