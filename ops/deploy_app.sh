#!/usr/bin/env bash
set -o errexit
set -o nounset

#--------------------------------------------------------------------------------------------------
# Create stack in AWS.
#
# @param $1 - The AWS region. us-east-1 used
# @param $2 - [Optional] Stack name. "app" used by default.
# @param $3 - [Optionsl] ELB Stack name.
# @param $4 - [Optional] Environment name. "qa" used by default
#--------------------------------------------------------------------------------------------------
function launch() {
  local region="${1}"
  local stack_name="${2}"
  local ELB_stack_name="${3}"
  local environment="${4}"

  local params=""
  params="${params:+${params} }ParameterKey=Name,ParameterValue=${stack_name}"
  params="${params:+${params} }ParameterKey=ELBStackName,ParameterValue=${ELB_stack_name}"
  params="${params:+${params} }ParameterKey=Environment,ParameterValue=${environment}"

  local tags=""
  tags="${tags:+${tags} }Key=service,Value=load-balancer"
  tags="${tags:+${tags} }Key=Environment,Value=${environment}"

  aws --output text cloudformation create-stack                             \
      --stack-name "${stack_name}"                                          \
      --region "${region}"                                                  \
      --template-body file://$(dirname $0)/app_ASG.yml                      \
      --parameters ${params}                                              \
      --capabilities CAPABILITY_IAM                                         \
      --tags ${tags}

    log "Stack creation launched"
}

function wait_complete() {
  local region="${1}"
  local stack_name="${2}"

  log "Waiting..."

  aws cloudformation wait stack-create-complete           \
    --region ${region}                                    \
    --stack-name ${stack_name}

  log "Stack creation complete"
}

#-------------------------------------------------------------------------------
# Log a message.
#-------------------------------------------------------------------------------
function log() {
  echo 1>&2 "INFO: $@"
}

#-------------------------------------------------------------------------------
# Emit an error message and then usage information and then exit the program.
#-------------------------------------------------------------------------------
function error() {
  echo 1>&2 "ERROR: $@"
}

#-------------------------------------------------------------------------------
# Emit an error message and then usage information and then exit the program.
#-------------------------------------------------------------------------------
function usage_error() {
  error "$@"
  echo 1>&2
  usage
  exit 1
}

#-------------------------------------------------------------------------------
# Emit the program's usage to the console.
#-------------------------------------------------------------------------------
function usage() {
    cat <<EOF
Usage: ${0#./} [OPTION]...

Options:

  --stack-name
      [Optional] Name of created stack. "app" is default.

 --elb-stack-name
      [Optional] Name of attached stack with ELB. "app-ELB" as default.

  --environment
      [Optional] Environment name.

  -h/--help
      Display this help message.
EOF
}

#-------------------------------------------------------------------------------
# Main program.
#-------------------------------------------------------------------------------
function main() {
  local stack_name="app"
  local ELB_stack_name="app-ELB"
  local environment='qa'
  local region="us-east-1"

  # Parse the arguments from the commandline.
  while [[ ${#} -gt 0 ]]; do
    case "${1}" in
      --stack-name)           stack_name="${2}"; shift;;
      --elb-stack-name)       ELB_stack_name="${2}"; shift;;
      --environment)          environment="${2}"; shift;;
      -h|--help)              usage; exit 0;;
      --)                     break;;
      -*)                     usage_error "Unrecognized option ${1}";;
    esac

    shift
  done

  # Finally create the stack
  launch                  \
    "${region}"           \
    "${stack_name}"       \
    "${ELB_stack_name}"   \
    "${environment}"

  wait_complete           \
    "${region}"           \
    "${stack_name}"
}

main "${@:-}"
