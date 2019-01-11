#!/usr/bin/env bash
set -o errexit
set -o nounset

#-------------------------------------------------------------------------------
# Log a message.
#-------------------------------------------------------------------------------
function log() {
  echo 1>&2 "$@"
}

#-------------------------------------------------------------------------------
# Display an error message to standard error and then exit the script with a
# non-zero exit code.
#-------------------------------------------------------------------------------
function error() {
  echo 1>&2 "ERROR: $@"
  echo 1>&2
  usage
  exit 1
}

#-------------------------------------------------------------------------------
# Retry a command until it returns an exit code of zero.
#
# @param $* - The command to run.
#-------------------------------------------------------------------------------
function wait_until() {
    until "${@}"; do
        log "Command failed: ${*}"
        sleep 10
        log "Retrying."
    done
}

#-------------------------------------------------------------------------------
# Determine which region the currently running instance is in.
#-------------------------------------------------------------------------------
function get_ec2_instance_region() {
  /opt/aws/bin/ec2-metadata --availability-zone |
  cut -d" " -f2 |
  sed "s/.$//g"
}

#-------------------------------------------------------------------------------
# Install a package, retrying if it fails.
#-------------------------------------------------------------------------------
function yum_install() {
  local package="${1}"

  while ! yum install -y "${package}"; do
    log "Failed to install ${package}"
    sleep 15
    log "Trying again."
  done
}

#-------------------------------------------------------------------------------
# Install Puppet
#-------------------------------------------------------------------------------
function install_puppet() {
  rpm -Uvh https://yum.puppet.com/puppet5/puppet5-release-el-6.noarch.rpm
  yum_install puppet-agent
  /opt/puppetlabs/bin/puppet module install puppetlabs-stdlib
}

#-------------------------------------------------------------------------------
# Install Dropwizard
#-------------------------------------------------------------------------------
function install_dropwizard() {
  local version="${1}"

  aws s3 cp s3://30daysdevops/nick/release/dropwizard-example-${version}-SNAPSHOT.jar /tmp/
  aws s3 cp s3://30daysdevops/nick/release/mysql.yml /tmp/
  aws s3 cp s3://30daysdevops/nick/app.pp ./ && \
  /opt/puppetlabs/bin/puppet apply app.pp

  sudo -u dropwizard /usr/bin/java                                               \
                     -jar /opt/dropwizard/dropwizard-example-${version}-SNAPSHOT.jar  \
                     server /opt/dropwizard/server.yml &
}

#-------------------------------------------------------------------------------
# Install Dropwizard host
#-------------------------------------------------------------------------------
function main() {
  local region=$(get_ec2_instance_region)
  local version="0.0.1"
  local environment="qa"
  local datadog_secret_name="datadog_api_key"

    while [[ ${#} -gt 0 ]]; do
    case "${1}" in
      --datadog-secret-name)    datadog_secret_name="${2}"
                                shift 2 ;;
      --version)                version="${2}"
                                shift 2 ;;
      *)                        error Unrecognized option "${1}" ;;
    esac
  done

  yum_install aws-cfn-bootstrap

  install_puppet

  install_dropwizard ${version}
}

#exec &> >(logger -t "cloud_init" -p "local0.info")

main "${@}"
