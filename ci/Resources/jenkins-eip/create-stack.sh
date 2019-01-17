#!/usr/bin/env bash
set -o errexit
set -o nounset

#--------------------------------------------------------------------------------------------------
# Create stack in AWS.
#
# @param $1 - The AWS region. us-east-1 used
# @param $2 - Stack name
# @param $3 - dns_name
# @param $4 - relative path from git root
# @param $5 - servive name - normally jenkins (for tags)
# @param $6 - environment - normally ci (for tags)
#--------------------------------------------------------------------------------------------------

function launch() {
  local dns_base=`echo ${3} | sed 's/^[^.]*\.\(.*\)/\1/'`
  local dns_subdomain=`echo ${3} | sed 's/^\([^.]*\)\..*/\1/'`

  local params=""
  params="${params:+${params} }ParameterKey=R53HostedZone,ParameterValue=${dns_base}"
  params="${params:+${params} }ParameterKey=R53DNSName,ParameterValue=${dns_subdomain}"

  local tags=""
  tags="${tags:+${tags} }Key=Service,Value=${service}"
  tags="${tags:+${tags} }Key=Environment,Value=${environment}"

  aws cloudformation create-stack                         \
    --stack-name "${stack_name}"                          \
    --region "${region}"                                  \
    --template-body file://${templete_path}/EIP.yml          \
    --parameters ${params}                                \
    --tags $tags

  log "Stack creation launched"
}

function wait_complete() {
  log "Waiting..."

  aws cloudformation wait stack-create-complete           \
    --region ${region}                                    \
    --stack-name ${stack_name}

  log "Stack creation complete"
}

#-------------------------------------------------------------------------------
# Add tags to EIP
#-------------------------------------------------------------------------------
function tag_eip() {

  local tags=""
  tags="${tags:+${tags} }Key=Service,Value=${service}"
  tags="${tags:+${tags} }Key=Environment,Value=${environment}"

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

  --dns-name
      [Optional] DNS Record for created IP. 'bastion.30daystodevops.me.uk' is default

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
  local dns_name="bastion.30daystodevops.me.uk"

  # Parse the arguments from the commandline.
  while [[ ${#} -gt 0 ]]; do
    case "${1}" in
      --region)               region="${2}"; shift;;
      --stack-name)           stack_name="${2}"; shift;;
      --dns-name)             dns_name="${2}"; shift;;
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
    "${dns_name}"

  wait_complete           \
    "${region}"           \
    "${stack_name}"

  tag_eip                 \
    "${region}"           \
    "${stack_name}"

}

main "${@:-}"
