#!/usr/bin/perl -w
#
# Facilitate Perl Module installation
# Arguments: 
#    test    - Show lis of installed and missing modules
#    install - Try to install missing modules using the CPAN
#    apt-get-install - install using apt-get when possible
#    rpm-install - install using rpm packages when possible
use strict;
use CPAN;

my $action = $ARGV[0] 
    or die "Missing required argument: action";

#DEPS is now a list of anonymous hashes with three keys 'cpan' 'apt' and 'rpm'.  Their contents should be fairly obvious, cpan is the name in cpan
#of the perl module.  apt is the name or names (space delimited) of the perl module, or perl modules that may be dependencies of the module in question
#if the module is not avaliable in the apt-get repository (installing dependencies makes the cpan install process more reliable though).  rpm is the 
#same idea as apt, but refers to the module name in the rpm repository.

my @DEPS = (
    {cpan=> 'CGI 3.20' , apt=> '', rpm=>''},
    {cpan=>'Ima::DBI 0.35', apt=> 'libima-dbi-perl', rpm=>'perl-Ima-DBI.noarch'},
    {cpan=>'Class::DBI 3.0.10', apt=> 'libclass-dbi-perl', rpm=>'perl-Class-DBI.noarch'},
    {cpan=>'Class::DBI::AbstractSearch', apt=> 'libclass-dbi-abstractsearch-perl', rpm=> 'perl-Class-DBI-AbstractSearch.noarch'},
    {cpan=>'Apache2::Request', apt=>'libapache2-request-perl', rpm=>''},
    {cpan=>'HTML::Mason 1.31',apt=>'libhtml-mason-perl',rpm=>'perl-HTML-Mason.noarch'},
    {cpan=>'Apache::Session 1.6', apt=>'libapache-session-perl', rpm=>'perl-Apache-Session.noarch'},
    {cpan=>'URI::Escape', apt=>'liburi-perl', rpm=>'perl-URI.noarch'},
    {cpan=>'DBIx::DataSource', apt=> 'libdbix-datasource-perl', rpm=>''},
    {cpan=>'GraphViz 2.02', apt=> 'graphviz', rpm=>''},
    {cpan=>'SQL::Translator 0.07', apt=>'libsql-translator-perl', rpm=>'perl-SQL-Translator.noarch'},
    {cpan=>'SNMP::Info 2.01', apt=>'libsnmp-info-perl', rpm=>'perl-SNMP-Info.noarch'},
    {cpan=>'NetAddr::IP', apt=>'libnetaddr-ip-perl', rpm=>'perl-NetAddr-IP.i686'},
    {cpan=>'Apache2::SiteControl 1.0', apt=>'', rpm=>''},
    {cpan=>'Log::Dispatch', apt=>'liblog-dispatch-perl', rpm=>'perl-Log-Dispatch.noarch'},
    {cpan=>'Log::Log4perl', apt=>'liblog-log4perl-perl', rpm=>'perl-Log-Log4perl.noarch'},
    {cpan=>'Parallel::ForkManager', apt=>'libparallel-forkmanager-perl', rpm=>'perl-Parallel-ForkManager.noarch'},
    {cpan=>'Net::IPTrie', apt=> '', rpm=>''},
    {cpan=>'Authen::Radius', apt=>'libauthen-radius-perl', rpm=>'perl-Authen-Radius.noarch'},
    {cpan=>'RRDs' , apt=>'librrds-perl', rpm=>''},
    {cpan=>'Test::More' , apt=> '', rpm=>''},
    {cpan=>'Test::Harness', apt=> 'libtest-harness-perl', rpm=>'perl-Test-Harness.i686'},
    {cpan=>'Net::IRR', apt=> '', rpm=>''},
    {cpan=>'Time::Local', apt=> 'libtime-local-perl', rpm=>''},
    {cpan=>'File::Spec',apt=> 'libfile-spec-perl', rpm=>''},
    {cpan=>'Net::Appliance::Session',apt=> '', rpm=>''},
    {cpan=>'BIND::Config::Parser', apt=>'libbind-confparser-perl', rpm=>''},
    {cpan=>'Net::DNS', apt=> 'libnet-dns-perl', rpm=>'perl-Net-DNS.i686'},
    {cpan=>'Text::ParseWords', apt=>'', rpm=>''},
    {cpan=>'Carp::Assert', apt=>'libcarp-assert-perl', rpm=>'perl-Carp-Assert.noarch'},
    {cpan=>'Digest::SHA', apt=> 'libdigest-sha-perl', rpm=>'perl-Digest-SHA1.i686'},
    {cpan=>'Net::DNS::ZoneFile::Fast 1.12', apt=> 'libnet-dns-sec-perl', rpm=>'perl-Net-DNS-SEC.noarch'}
    ) ;

if ( $action eq 'test' ){
	run_test();
}

elsif ( $action eq 'install' || $action eq 'apt-get-install' || $action eq 'rpm-install'){
    
	my $uid = `id -u`;
	if($uid && $uid != 0){
		print "You must be root to install the required dependencies\n";
		exit(1);
	}
	if($action eq 'apt-get-install' || $action eq 'rpm-install'){
        	my $arg_builder = "";
		my $program = '';
		if($action eq 'apt-get-install'){
			$program = 'apt-get -y install ';
		}
		else{
			$program = 'yum install ';
		}

        	foreach my $anon_hash (@DEPS){
			if($action eq 'apt-get-install'){
            			$arg_builder .= " ".$anon_hash->{'apt'};
  			}
			else{
				$arg_builder .= " ".$anon_hash->{'rpm'};
			}
        	}

		#now that we have a huge list of things to install via apt-get, lets run the command
		my $results = system("$program $arg_builder");
        
		#error code for command not found
		if($results > 1){
			if($results == 127){
				print "It looks like we can't find your package management program, ";
			}
			elsif($results > 1){
				print "Seems like there was a problem running your package management program, ";
			}
			print " would you like to continue and install all modules through CPAN [y/n]? [y] ";
			$a = <STDIN>;
			if($a =~ /(N|n)/){
				exit(1);
            		}
		}
	}		
	#we call this regardless beacuse it checks to see if a module is installed 
	#before trying anything, so lets just pass the whole hash in and if 
	#something didn't take for whatever reason, hopefully it will be fixed by CPAN 
	install_modules_cpan();
    
	#finally, lets call run_test to show the user if anything is missing
	print "===============RESULTS===============\n";
	run_test();
}

sub install_modules_cpan{
	$CPAN::Config->{prerequisites_policy} = 'follow';
	foreach my $anon_hash (@DEPS){
		my $module = $anon_hash->{'cpan'};
		eval "use $module";
		if ( $@ ){
			$module =~ s/^(.*)\s+.*/$1/;
			eval {
				CPAN::Shell->install($module);
			};

			if ( my $e = $@ ){
				print $e;
			}
		}
	}
}

sub run_test{
	foreach my $anon_hash (@DEPS){
		my $module = $anon_hash->{'cpan'};
		eval "use $module";
		print $module, "................";
		if ( $@ ){
			print "MISSING";
		}
		else{
			print "installed";
		}
		print "\n";
	}
}

