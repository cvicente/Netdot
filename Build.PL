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
	'CGI' => '4.43',
	'Class::DBI' => '3.0.17',
	'Class::DBI::AbstractSearch' => '0.0.7',
	'HTML::Mason' => '1.58',
	'Apache::Session' => '1.93',
	'URI::Escape' => '1.76',
	'SQL::Translator' => '0.11024',
	'SNMP::Info' => '3.68',
	'NetAddr::IP' => '4.079',
	'Apache2::AuthCookie' => '3.27',
	'Apache2::SiteControl' => '1.05',
	'Log::Dispatch' => '2.68',
	'Log::Log4perl' => '1.49',
	'Parallel::ForkManager' => '2.02',
	'Net::Patricia' => '1.22',
	'Authen::Radius' => '0.29',
	'Net::IRR' => '0.08',
	'Time::Local' => '1.28',
	'File::Spec' => '3.75',
	'Net::Appliance::Session' => '4.300005',
	'BIND::Config::Parser' => '0.01',
	'Net::DNS' => '1.20',
	'Digest::SHA' => '6.02',
	'Net::DNS::ZoneFile::Fast' => '1.27',
	'Socket6' => '0.29',
	'XML::Simple' => '2.25'
    },
    test_requires => {
	'Test::Exception' => '0.43',
	'Test::File::Contents' => '0.23',
	'Test::More' => '1.302164',
	'Test::Pod' => '1.52',
	'Carp::Assert' => '0.21'
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
