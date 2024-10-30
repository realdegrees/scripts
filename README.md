# Scripts

This repository is a collection of useful scripts organized by category.

## Table of Contents

| Category      | Script            | Description                     |
|---------------|--------------------|---------------------------------|
| **Git**       | `runner.sh`	     | Spins up a basic GitHub runner for the supplied repo in a docker container. It can also list all current runners and run multiple runners in parallel without affecting each other. The GitHub Personal-Access-Token is supplied via `pass git/pat`.                                |

> Scripts can be run directly without a manual installation.  
Simply setup an `alias` that downloads and executes the script.
```bash
get_runner_script() {
  if [ -f ~/scripts/git/runner.sh ]; then 
        ~/scripts/git/runner.sh "$@"
    else 
        curl -sL https://github.com/realdegrees/scripts/raw/master/git/runner.sh | bash -s -- "$@"
    fi
}
alias runner='get_runner_script'
```