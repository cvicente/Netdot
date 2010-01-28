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
    or die "
Arguments:
	test    - Show lis of installed and missing modules
	install - Try to install missing modules using the CPAN
	apt-get-install - install using apt-get when possible
	rpm-install - install using rpm packages when possible
";

#DEPS is now a list of anonymous hashes with three keys 'cpan' 'apt' and 'rpm'.  Their contents should be fairly obvious, cpan is the name in cpan
#of the perl module.  apt is the name or names (space delimited) of the perl module, or perl modules that may be dependencies of the module in question
#if the module is not avaliable in the apt-get repository (installing dependencies makes the cpan install process more reliable though).  rpm is the 
#same idea as apt, but refers to the module name in the rpm repository.

my @DEPS = (
    {cpan=> 'Module::Build' , apt=> 'libmodule-build-perl', rpm=>'perl-Module-Build'},
    {cpan=> 'CGI 3.20' , apt=> '', rpm=>''},
    {cpan=>'Ima::DBI 0.35', apt=> 'libima-dbi-perl', rpm=>'perl-Ima-DBI'},
    {cpan=>'Class::DBI 3.0.10', apt=> 'libclass-dbi-perl', rpm=>'perl-Class-DBI'},
    {cpan=>'Class::DBI::AbstractSearch', apt=> 'libclass-dbi-abstractsearch-perl', rpm=> 'perl-Class-DBI-AbstractSearch'},
    {cpan=>'Apache2::Request', apt=>'libapache2-request-perl', rpm=>'libapreq2 libapreq2-devel perl-libapreq2'},
    {cpan=>'HTML::Mason 1.31',apt=>'libhtml-mason-perl',rpm=>'perl-HTML-Mason'},
    {cpan=>'Apache::Session 1.6', apt=>'libapache-session-perl', rpm=>'perl-Apache-Session'},
    {cpan=>'URI::Escape', apt=>'liburi-perl', rpm=>'perl-URI'},
    {cpan=>'DBIx::DataSource', apt=> 'libdbix-datasource-perl', rpm=>''},
    {cpan=>'GraphViz 2.02', apt=> 'graphviz', rpm=>'graphviz graphviz-devel perl-GraphViz'},
    {cpan=>'SQL::Translator 0.07', apt=>'libsql-translator-perl', rpm=>'perl-SQL-Translator'},
    {cpan=>'SNMP::Info 2.01', apt=>'libsnmp-info-perl', rpm=>'perl-SNMP-Info'},
    {cpan=>'NetAddr::IP', apt=>'libnetaddr-ip-perl', rpm=>'perl-NetAddr-IP'},
    {cpan=>'Apache2::AuthCookie', apt=>'', rpm=>''},
    {cpan=>'Apache2::SiteControl 1.0', apt=>'', rpm=>''},
    {cpan=>'Log::Dispatch', apt=>'liblog-dispatch-perl', rpm=>'perl-Log-Dispatch'},
    {cpan=>'Log::Log4perl', apt=>'liblog-log4perl-perl', rpm=>'perl-Log-Log4perl'},
    {cpan=>'Parallel::ForkManager', apt=>'libparallel-forkmanager-perl', rpm=>'perl-Parallel-ForkManager'},
    {cpan=>'Net::IPTrie', apt=> '', rpm=>''},
    {cpan=>'Authen::Radius', apt=>'libauthen-radius-perl', rpm=>'perl-Authen-Radius'},
    {cpan=>'RRDs' , apt=>'librrds-perl', rpm=>''},
    {cpan=>'Test::More' , apt=> '', rpm=>''},
    {cpan=>'Test::Harness', apt=> 'libtest-harness-perl', rpm=>'perl-Test-Harness'},
    {cpan=>'Net::IRR', apt=> '', rpm=>''},
    {cpan=>'Time::Local', apt=> 'libtime-local-perl', rpm=>''},
    {cpan=>'File::Spec',apt=> 'libfile-spec-perl', rpm=>''},
    {cpan=>'Net::Appliance::Session',apt=> '', rpm=>''},
    {cpan=>'BIND::Config::Parser', apt=>'libbind-confparser-perl', rpm=>''},
    {cpan=>'Net::DNS', apt=> 'libnet-dns-perl', rpm=>'perl-Net-DNS'},
    {cpan=>'Text::ParseWords', apt=>'', rpm=>''},
    {cpan=>'Carp::Assert', apt=>'libcarp-assert-perl', rpm=>'perl-Carp-Assert'},
    {cpan=>'Digest::SHA', apt=> 'libdigest-sha-perl', rpm=>'perl-Digest-SHA1'},
    {cpan=>'Net::DNS::ZoneFile::Fast 1.12', apt=> 'libnet-dns-sec-perl', rpm=>'perl-Net-DNS-SEC'}
    ) ;

if ( $action eq 'test' ){
	run_test();
}

elsif ( $action eq 'install' || $action eq 'apt-get-install' || $action eq 'rpm-install'){
    	my $installed_epel = 0;
	my $uid = `id -u`;
	if($uid && $uid != 0){
		print "You must be root to install the required dependencies\n";
		exit(1);
	}

	if($action eq 'rpm-install'){
		print "If you are using Red Hat Enterprise Linux (RHEL), be aware that the official repository does not include many of the perl packages that Netdot requires.  Would you like to use the EPEL (Extra Packages for Enterprise Linux) repository to help install these packages? [y/n]";
		my $ans = <STDIN>;
		if($ans =~ /(Y|y)/){
			$installed_epel = 1;
			system("rpm -Uvh http://download.fedora.redhat.com/pub/epel/5/i386/epel-release-5-3.noarch.rpm");	
		}
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
		}
	}		

	print " would you like to continue and install all modules through CPAN [y/n]? [y] ";
	$a = <STDIN>;
	if($a =~ /(Y|y)/){
	    #we call this regardless beacuse it checks to see if a module is installed 
	    #before trying anything, so lets just pass the whole hash in and if 
	    #something didn't take for whatever reason, hopefully it will be fixed by CPAN 
	    install_modules_cpan();
	}

	#finally, lets call run_test to show the user if anything is missing
	print "===============RESULTS===============\n";
	run_test();
	
	if($installed_epel){
		print "Would you like to uninstall EPEL at this time? [y/n]";
		my $ans = <STDIN>;
		if($ans =~ /(Y|y)/){
			system("yum erase epel-release-5-3.noarch");
		}
	}
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

