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

package { 'httpd24':
  ensure  => installed,
  require => Exec['yum-update'],
}

package { 'datadog-agent':
  ensure  => installed,
  require => Yumrepo['Datadog'],
}

service { 'httpd':
  ensure  => running,
  enable  => true,
  require => Package['httpd24'],
}

service { 'datadog-agent':
  ensure     => running,
  enable     => true,
  provider   => 'upstart',
  hasrestart => true,
  subscribe  => File['/etc/datadog-agent/datadog.yaml'],
}

file { '/etc/datadog-agent/datadog.yaml':
  ensure  => file,
  mode    => '0640',
  owner   => dd-agent,
  group   => dd-agent,
  content => "api_key: 999bec7755b4411e669ecbb204ccd5ab\n",
  # source => '/etc/datadog-agent/datadog.yaml.example',
  notify  => Service['datadog-agent']
}

file { '/var/www/html/index.html':
  ensure  => file,
  content => '<html>
              <body>
              <h1>Congratulations, you have successfully launched the
                  AWS CloudFormation sample.</h1>
              </body>
              </html>',
  require => Package['httpd24'],        # require 'apache2' package
}
