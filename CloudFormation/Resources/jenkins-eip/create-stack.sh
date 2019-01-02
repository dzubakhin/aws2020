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

  local tags=""
  tags="${tags:+${tags} }Key=service,Value=jenkins"

  aws cloudformation create-stack                         \
    --stack-name "${stack_name}"                          \
    --region "${region}"                                  \
    --template-body file://$(dirname $0)/EIP.yml          \
    --tags $tags

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

function tag_eip() {
  local region="${1}"
  local stack_name="${2}"

  local tags=""
  tags="${tags:+${tags} }Key=service,Value=jenkins"

  log "Tagging EIP"

  eip_id=`aws --output text --region ${region} cloudformation list-exports | \
          grep "${stack_name}-ElasticIP" | cut -f 4`
  aws --region ${region} ec2 create-tags --resources ${eip_id} --tags ${tags}
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
      [Optional] Name of created stack. "jenkins-EIP" is default.

  -h/--help
      Display this help message.
EOF
}

#-------------------------------------------------------------------------------
# Main program.
#-------------------------------------------------------------------------------
function main() {
  local stack_name="jenkins-EIP"
  local region="us-east-1"

  # Parse the arguments from the commandline.
  while [[ ${#} -gt 0 ]]; do
    case "${1}" in
      --stack-name)           stack_name="${2}"; shift;;
      -h|--help)              usage; exit 0;;
      --)                     break;;
      -*)                     usage_error "Unrecognized option ${1}";;
    esac

    shift
  done

  # Finally create the stack
  launch                  \
    "${region}"           \
    "${stack_name}"

  wait_complete           \
    "${region}"           \
    "${stack_name}"

  tag_eip                 \
    "${region}"           \
    "${stack_name}"

}

main "${@:-}"
