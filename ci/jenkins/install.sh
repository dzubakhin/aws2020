#!/usr/bin/env bash
set -o errexit
set -o nounset

#-------------------------------------------------------------------------------
# Log a message.
#-------------------------------------------------------------------------------
function log() {
  echo 1>&2 "INFO: $@"
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
# Determine the ID of the currently running EC2 instance.
#-------------------------------------------------------------------------------
function get_ec2_instance_id() {
  /opt/aws/bin/ec2-metadata --instance-id |
  cut -d" " -f2
}

#-------------------------------------------------------------------------------
# Determine current availability zone
#-------------------------------------------------------------------------------
function get_ec2_instance_availability_zone() {
  /opt/aws/bin/ec2-metadata --availability-zone |
  cut -d" " -f2
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
# Determine the value of a tag on this instance.
#
# This is determined from the EC2 tags on the current instance.
#-------------------------------------------------------------------------------
function get_ec2_instance_tag() {
  local tag="${1}"
  local region=$(get_ec2_instance_region)
  local instance_id=$(get_ec2_instance_id)
  local value=""

    value=$(wait_until aws ec2 describe-tags                            \
                    --region "${region}"                                \
                    --filters Name=resource-id,Values="${instance_id}"  \
                              Name=key,Values="${tag}"                  \
                    --output text                                       \
                    --query 'Tags[0].Value')

  echo "${value}"
}

#-------------------------------------------------------------------------------
# Determine last created snapshot ID for Jenkins
#
# @param $1 - The region where the host is located.
#-------------------------------------------------------------------------------
function get_jenkins_snapshot() {
  local region="${1}"

  local snapshot_id=$(wait_until aws ec2 describe-snapshots                                                   \
                        --region ${region}                                                                    \
                        --filters Name=status,Values=completed                                                \
                                  Name=tag:Service,Values=${service}                                             \
                        --query 'Snapshots[].[SnapshotId, StartTime] | reverse(sort_by(@, &[1])) | [0] | [0]' \
                        --output text)

  if [[ ${snapshot_id} = "None" || -z ${snapshot_id} ]]; then
    log "Valid snapshot not found."
    echo ""
  else
    log "Found snapshot ${snapshot_id}"
    echo "${snapshot_id}"
  fi
}

#-------------------------------------------------------------------------------
# Determine public IP for Jenkins
#
# @param $1 - The region where the host is located.
#-------------------------------------------------------------------------------
function get_jenkins_public_ip() {
  local region="${1}"

  local public_ip=$(wait_until aws ec2  describe-addresses                 \
                                --region ${region}                         \
                                --filter Name=tag:Service,Values=${service}   \
                                --query 'Addresses[].[PublicIp]'           \
                                --output text)

  if [[ -z ${public_ip} ]]; then
    log "Public IP not found."
    echo ""
  else
    log "Found IP ${public_ip}"
    echo "${public_ip}"
  fi
}

#-------------------------------------------------------------------------------
# Determine the physical ID of the assigned EBS data volume to attach and mount
#
# This is determined from the EC2 tags on the current instance.
# @param $1 - The region where the host is located.
#-------------------------------------------------------------------------------
function get_jenkins_data_volume() {
  local region=${1}

  local volume_id=$(wait_until aws ec2 describe-volumes                        \
                         --region ${region}                                    \
                         --filters Name=status,Values=available                \
                                   Name=tag:Service,Values=${service}             \
                         --query 'Volumes[].[VolumeId, CreateTime] | reverse(sort_by(@, &[1])) | [0] | [0]'          \
                         --output text)

  if [[ ${volume_id} = "None" || -z ${volume_id} ]]; then
    log "Valid volume not found."
    echo ""
  else
    log "Found volume ${volume_id}"
    echo "${volume_id}"
  fi
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
# Set hostname and perform any necessary related tasks.
#
# @param $1 - The desired hostname of the server.
#-------------------------------------------------------------------------------
function set_hostname() {
  local hostname="${1}"
  hostname "${hostname}"

  local expr="s/^([[:space:]]*HOSTNAME=)[^[:space:]]*/\1${hostname}/"
  sed -ri "${expr}" /etc/sysconfig/network
}

#-------------------------------------------------------------------------------
# Attach EBS volume and setup to create backup snapshots
# @param $1 - Volume ID
# @param $2 - Device for mount EBS volume
# @param $3 - Current region
#-------------------------------------------------------------------------------
function attach_volume() {
  local volume_id="${1}"
  local device="${2}"
  local region="${3}"

# Attach the EBS data volume as /dev/sdh
  wait_until aws ec2 attach-volume                    \
                 --region ${region}                   \
                 --volume-id ${volume_id}             \
                 --instance-id $(get_ec2_instance_id) \
                 --device ${device}

  #Wait until EBS volume attached.
  while [[ ! -b ${device} ]]; do
    log "Waiting for AWS to finish attaching the EBS volume. Looping..."
    sleep 10
  done
  log "EBS volume ${volume_id} attached."
}

#-------------------------------------------------------------------------------
# Attach, mount, and prepare the Jenkins EBS data volume.
#
# @param $1 - The region where the host is located.
# @param $2 - The current environment
#-------------------------------------------------------------------------------
function mount_jenkins_data_volume() {
  local region="${1}"
  local availability_zone="$(get_ec2_instance_availability_zone)"
  local volume_id="$(get_jenkins_data_volume ${region})"
  local created_volume=""
  local snapshot_id="$(get_jenkins_snapshot ${region})"
  local mount_point="/var/lib/jenkins"
  local device="/dev/sdh"

  #Valid volume found
  if [[ -n "${volume_id}" ]]; then
    #Attach founded valid volume
    log "Attaching valid volume ${volume_id}"
    attach_volume ${volume_id} ${device} ${region}

  #Snapshot exist and volume not found
  elif [[ -n ${snapshot_id} && -z ${volume_id} ]]; then
    #Restore volume from last created snapshot
    log "Restoring volume from snapshot ${snapshot_id}"
    created_volume=$(wait_until aws ec2 create-volume                                           \
                   --region ${region}                                                           \
                   --availability-zone ${availability_zone}                                     \
                   --snapshot-id ${snapshot_id}                                                 \
                   --volume-type standard                                                       \
                   --query '[VolumeId]'                                                         \
                   --output text)
    log "Volume ${created_volume} from snapshot ${snapshot_id} restored"

    #Attach restored from snapshot volume
    attach_volume ${created_volume} ${device} ${region}

  #Snapshot not found, volume not found, create new volume
  else
    log "Creating new volume"
    created_volume=$(wait_until aws ec2 create-volume                                           \
                   --region ${region}                                                           \
                   --availability-zone ${availability_zone}                                     \
                   --size 8                                                                  \
                   --volume-type standard                                                       \
                   --query '[VolumeId]'                                                         \
                   --output text)
    log "New volume ${created_volume} created"

    #Attach new created volume
    attach_volume ${created_volume} ${device} ${region}

    # Install the xfsprogs package since we need an XFS volume
    yum_install xfsprogs
    log "Installed xfsprogs package."

    # Create a new file system
    mkfs.xfs -f ${device}
  fi

  # Create the mount point
  mkdir -p ${mount_point}
  log "Created mount point."

  # Add a new entry for the volume to /etc/fstab
  cat - >> /etc/fstab <<EOF
# device    mount point              type  options   dump  pass
${device}  ${mount_point}           xfs   defaults  0     0
EOF
  log "Added fstab entry."

  # Mount the file system as /var/lib/jenkins
  mount ${mount_point}
  log "Mounted data volume."
}

#-------------------------------------------------------------------------------
# Associates an Elastic IP address with jenkins host
#-------------------------------------------------------------------------------
function associate_eip() {
  local region="${1}"
  local public_ip=$(get_jenkins_public_ip ${region})
  local instance_id=$(get_ec2_instance_id)
  local allocation_id=""

  allocation_id=$(wait_until aws ec2 associate-address        \
                             --region ${region}               \
                             --instance-id ${instance_id}     \
                             --public-ip ${public_ip}         \
                             --output text)
  log "Allocation ID is ${allocation_id} for EIP ${public_ip}"
}

#-------------------------------------------------------------------------------
# Install a Docker&StartJenkins
#-------------------------------------------------------------------------------
function install_jenkins() {
          yum install -y docker
          service docker start
          usermod -a -G docker root
          curl -L "https://github.com/docker/compose/releases/download/1.23.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
          chmod +x /usr/bin/docker-compose
          chown -R 1000 /var/lib/jenkins
          aws s3 cp s3://30daysdevops/scripts/jenkins/docker-compose.yml /home/ec2-user/docker-compose.yml
          docker-compose -f /home/ec2-user/docker-compose.yml up -d
}

#-------------------------------------------------------------------------------
# Install fail2ban
#-------------------------------------------------------------------------------
function install_fail2ban() {
          yum_install fail2ban
          chkconfig fail2ban on
          service fail2ban start
}

#-------------------------------------------------------------------------------
# Install and configure the DataDog agent on the current instance.
#
# @param $1 - The API key to connect to DataDog with.
#-------------------------------------------------------------------------------
function install_datadog() {
  local region="${1}"
  local datadog_secret_name="${2}"

  log "Installing jq..."
  yum_install jq
  log "Done."

  log "Getting Datadog API key from Secret Manager"
  local api_key=$(wait_until aws secretsmanager get-secret-value                     \
                                                --region ${region}                   \
                                                --secret-id ${datadog_secret_name}   \
                                                --output json                        \
                                                --version-stage AWSCURRENT |         \
                                                jq ".SecretString" -r |              \
                                                jq ".key" -r)
  log "Datadog API key is ${api_key}"

  log "Installing datadog-agent..."
  DD_API_KEY=${api_key} bash -c "$(curl -L https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh)"
  log "Done."

  log "Configuring datadog..."
  cat > /etc/datadog-agent/datadog.yaml <<EOF
api_key: ${api_key}
logs_enabled: true
listeners:
  - name: docker
config_providers:
  - name: docker
    polling: true
EOF
  cat > /etc/datadog-agent/conf.d/docker.d/conf.yaml <<EOF
logs:
    - type: docker
      service: jenkins
      source: docker
EOF
  cat > /etc/datadog-agent/conf.d/docker.d/docker_daemon.yaml <<EOF
init_config:

instances:
    - url: "unix://var/run/docker.sock"
      new_tag_names: true
EOF
  usermod -a -G docker dd-agent
  log "Done."

  log "Starting datadog-agent..."
  restart datadog-agent
  log "Done."
}

#-------------------------------------------------------------------------------
# Install Jenkins.
#-------------------------------------------------------------------------------
function main() {
  local region=$(get_ec2_instance_region)
  local hostname=""
  local datadog_secret_name="datadog_api_key"
  local service="jenkins"

    while [[ ${#} -gt 0 ]]; do
    case "${1}" in
      --datadog-secret-name)    datadog_secret_name="${2}"
                                shift 2 ;;
      --hostname)               hostname="${2}"
                                shift 2 ;;
      --service)                service="${2}"
                                shift 2 ;;
      *)                        error Unrecognized option "${1}" ;;
    esac
  done

  wait_until yum update -y

  # Set the hostname
  set_hostname ${hostname}

  mount_jenkins_data_volume ${region}

  associate_eip ${region}

  install_datadog ${region} ${datadog_secret_name}

  install_fail2ban

  install_jenkins
}

exec &> >(logger -t "cloud_init" -p "local0.info")

main "${@}" &