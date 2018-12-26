exec { 'yum-update':
  command => '/usr/bin/yum -y update'
}

package { 'httpd24':
  ensure  => installed,
  require => Exec['yum-update'],
}

service { 'httpd':
  ensure  => running,
  enable  => true,
  require => Package['httpd24'],
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
