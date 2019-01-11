$var_json = generate('/usr/bin/aws', '--output', 'json', '--region',
  'us-east-1', 'secretsmanager', 'get-secret-value',
  '--secret-id', 'datadog_api_key')
$secret_data = parsejson($var_json)
$datadog_api_key = $secret_data['SecretString'].split(':')[1].split('"')[1]

yumrepo { 'Datadog':
  ensure   => present,
  name     => 'datadog',
  baseurl  => 'https://yum.datadoghq.com/stable/6/x86_64/',
  enabled  => 1,
  gpgcheck => 1,
  gpgkey   => 'https://yum.datadoghq.com/DATADOG_RPM_KEY.public'
}

exec { 'yum-update':
  command => '/usr/bin/yum -y update'
}

package { 'java-1.8.0-openjdk':
  ensure  => installed,
  require => Exec['yum-update'],
}

package { 'datadog-agent':
  ensure  => installed,
  require => Yumrepo['Datadog'],
}

service { 'datadog-agent':
  ensure     => running,
  enable     => true,
  # provider   => 'upstart',
  hasrestart => true,
  subscribe  => File['/etc/datadog-agent/datadog.yaml'],
}

file { '/etc/datadog-agent/datadog.yaml':
  ensure  => file,
  mode    => '0640',
  owner   => dd-agent,
  group   => dd-agent,
  content => "api_key: ${datadog_api_key}\n",
  # source => '/etc/datadog-agent/datadog.yaml.example',
  notify  => Service['datadog-agent']
}

user { 'dropwizard':
  ensure  => present,
}

file {'/opt/dropwizard':
  ensure  => directory,
  mode    => '0755',
  owner   => 'dropwizard',
  require => User['dropwizard']
}

file {'/opt/dropwizard/dropwizard-example-0.0.1-SNAPSHOT.jar':
  ensure  => file,
  mode    => '0644',
  source  => 'file:///tmp/dropwizard-example-0.0.1-SNAPSHOT.jar',
  require => File['/opt/dropwizard']
}

file {'/opt/dropwizard/server.yml':
  ensure  => file,
  mode    => '0644',
  source  => 'file:///tmp/mysql.yml',
  require => File['/opt/dropwizard']
}

exec { 'Run app':
  cwd     => '/opt/dropwizard',
  command => '/usr/bin/java -jar /opt/dropwizard/dropwizard-example-0.0.1-SNAPSHOT.jar server /opt/dropwizard/mysql.yml &',
  user    => 'dropwizard',
  require => [File['/opt/dropwizard'], Package['java-1.8.0-openjdk']]
}
