use strict;
use warnings;
use Module::Build;

Module::Build->new(
  module_name => 'Netdot',
  license     => 'gpl',
  dynamic_config => 1,
    configure_requires => {
    'Module::Build' => '0.42',
    },
    build_requires => {
    },
    requires => {
	'GraphViz' => '2.24',
	'CGI' => '4.38',
	'Class::DBI' => '3.0.17',
	'Class::DBI::AbstractSearch' => '0.0.7',
	'Apache2::Request' => '1.34',
	'HTML::Mason' => '1.58',
	'Apache::Session' => '1.93',
	'URI::Escape' => '1.73',
	'SQL::Translator' => '0.11024',
	'SNMP::Info' => '3.46',
	'NetAddr::IP' => '4.079',
	'Apache2::AuthCookie' => '3.27',
	'Apache2::SiteControl' => '1.01',
	'Log::Dispatch' => '2.67',
	'Log::Log4perl' => '1.49',
	'Parallel::ForkManager' => '1.19',
	'Net::Patricia' => '1.22',
	'Authen::Radius' => '0.26',
	'Net::IRR' => '0.08',
	'Time::Local' => '1.25',
	'File::Spec' => '3.74',
	'Net::Appliance::Session' => '4.300001',
	'BIND::Config::Parser' => '0.01',
	'Net::DNS' => '1.15',
	'Digest::SHA' => '6.01',
	'Net::DNS::ZoneFile::Fast' => '1.24',
	'Socket6' => '0.28',
	'XML::Simple' => '2.24'
    },
    test_requires => {
	'Test::Exception' => '0.43',
	'Test::File::Contents' => '0.23',
	'Test::More' => '1.302083',
	'Test::Pod' => '1.51'
    },
    meta_merge => {
	resources => {
	    homepage => 'https://github.com/cvicente/Netdot/',
	    bugtracker => 'https://github.com/cvicente/Netdot/issues',
	    repository => 'https://github.com/cvicente/Netdot',
	    IRC => 'irc://irc.freenode.org/#netdot',
	},
    },
    )->create_build_script;
