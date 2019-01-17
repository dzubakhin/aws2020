#!/usr/bin/env bash
set -o errexit
set -o nounset

#--------------------------------------------------------------------------------------------------
# Create stack in AWS.
#
# @param $1 - The AWS region. us-east-1 by default
# @param $2 - Stack name
# @param $3 - Size of volume
# @param $4 - relative path to templete from git root
# @param $5 - environment to tagging
#--------------------------------------------------------------------------------------------------
function launch() {
  local region="${1}"
  local stack_name="${2}"
  local size="${3}"
  local templete_path="${4}"
  local service="${5}"
  local environment="${6}"

  local tags=""
  tags="${tags:+${tags} }Key=Service,Value=${service}"
  tags="${tags:+${tags} }Key=Environment,Value=${environment}"

  local params=""
  params="${params:+${params} }ParameterKey=Size,ParameterValue=${size}"

  aws cloudformation create-stack                         \
    --stack-name "${stack_name}"                          \
    --region "${region}"                                  \
    --template-body file://${templete_path}/ebs-volume.yaml  \
    --parameters ${params}                                \
    --tags $tags                                \
    --capabilities CAPABILITY_IAM
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
      [Optional] Name of created stack. "S3bucket" is default.

  --size
      [Optional] Size in GB of created EBS volume

  -h/--help
      Display this help message.
EOF
}

#-------------------------------------------------------------------------------
# Main program.
#-------------------------------------------------------------------------------
function main() {
  local stack_name="jenkins-ebs-volume"
  local size="8"
  local region="us-east-1"
  local templete_path="$(dirname $0)"
  local service="jenkins"
  local environment="ci"

  # Parse the arguments from the commandline.
  while [[ ${#} -gt 0 ]]; do
    case "${1}" in
      --region)               region="${2}"; shift;;
      --stack-name)           stack_name="${2}"; shift;;
      --size)                 size="${2}"; shift;;
      --templete-path)        templete_path="${2}"; shift;;
      --service)              service="${2}"; shift;;
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
    "${size}"       \
    "${templete_path}"       \
    "${service}"       \
    "${environment}"
}

main "${@:-}"
