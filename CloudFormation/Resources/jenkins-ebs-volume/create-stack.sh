#!/usr/bin/env bash
set -o errexit
set -o nounset

#--------------------------------------------------------------------------------------------------
# Create stack in AWS.
#
# @param $1 - The AWS region. us-east-1 used
# @param $2 - [Optional] Stack name. "S3Bucket" used by default.
# @param $3 - Size of volume
#--------------------------------------------------------------------------------------------------
function launch() {
  local region="${1}"
  local stack_name="${2}"
  local size="${3}"

  local params=""
  params="${params:+${params} }ParameterKey=Size,ParameterValue=${size}"

  aws cloudformation create-stack                         \
    --stack-name "${stack_name}"                          \
    --region "${region}"                                  \
    --template-body file://$(dirname $0)/ebs-volume.yaml  \
    --parameters ${params}
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

  # Parse the arguments from the commandline.
  while [[ ${#} -gt 0 ]]; do
    case "${1}" in
      --stack-name)           stack_name="${2}"; shift;;
      --size)                 size="${2}"; shift;;
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
    "${size}"

}

main "${@:-}"
