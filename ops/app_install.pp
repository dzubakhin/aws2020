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

yumrepo { 'epel repo':
  ensure    => 'present',
  name      => 'epel',
  descr     => 'Extra Packages for Enterprise Linux 6 - $basearch',
  enabled   => '1',
  gpgcheck  => '1',
  target    => '/etc/yum.repo.d/epel.repo',
}

exec { 'easyinstall':
  command => '/usr/bin/pip install supervisor'
}

package { 'supervisor':
  ensure  => installed,
  require => Exec['easyinstall'],
}

service { 'supervisord':
  ensure => running,
  enable => true,
  }

package { 'java-1.8.0-openjdk':
  ensure  => installed,
}

exec { 'Set alternatives':
  command => '/usr/sbin/alternatives --set java /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/java',
  require => Package['java-1.8.0-openjdk'],
}

file {'/etc/supervisord.conf':
  ensure  => file,
  mode    => '0644',
  source  => 'file:///tmp/supervisord.conf',
  notify  => Service['supervisord'],
}

package { 'datadog-agent':
  ensure  => installed,
  require => Yumrepo['Datadog'],
}

service { 'datadog-agent':
  ensure     => running,
  enable     => true,
  provider   => 'upstart',
  hasrestart => true,
  subscribe  => File['/etc/datadog-agent/datadog.yaml'],
  require => Package['datadog-agent'],
}

file { '/etc/datadog-agent/datadog.yaml':
  ensure  => file,
  mode    => '0640',
  owner   => dd-agent,
  group   => dd-agent,
  content => "api_key: ${datadog_api_key}\nlogs_enabled: true",
  # source => '/etc/datadog-agent/datadog.yaml.example',
  notify  => Service['datadog-agent']
}
file {'/etc/datadog-agent/conf.d/dropwizard.d':
  ensure  => directory,
  mode    => '0644',
  owner   => 'dd-agent',
}
file {'/etc/datadog-agent/conf.d/dropwizard.d/conf.yaml':
  ensure  => file,
  mode    => '0644',
  owner   => dd-agent,
  group   => dd-agent,
  source  => 'file:///tmp/conf.yaml',
  require => File['/etc/datadog-agent/conf.d/dropwizard.d'],
  notify  => Service['datadog-agent']
}
user { 'dropwizard':
  ensure  => present,
  require => Package['supervisor'],
  notify  => Service['supervisord'],
}
file {'/opt/dropwizard':
  ensure  => directory,
  mode    => '0755',
  owner   => 'dropwizard',
  require => User['dropwizard']
}
file {'/var/log/supervisor':
  ensure  => directory,
  mode    => '0755',
  group   => 'dd-agent',
  require => File['/etc/supervisord.conf']
}
file {'/opt/dropwizard/mysql.yml':
  ensure  => file,
  mode    => '0644',
  source  => 'file:///tmp/mysql.yml',
  require => [File['/opt/dropwizard'], File['/etc/supervisord.conf']]
}
file {'/opt/dropwizard/dropwizard.jar':
  ensure  => file,
  mode    => '0644',
  source  => 'file:///tmp/dropwizard.jar',
  require => [File['/opt/dropwizard'], File['/etc/supervisord.conf']]
}
