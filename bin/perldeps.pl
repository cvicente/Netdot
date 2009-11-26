#!/usr/bin/perl -w
#
# Facilitate Perl Module installation
# Arguments: 
#    test    - Show lis of installed and missing modules
#    install - Try to install missing modules using the CPAN
#    apt-get-install - install using apt-get when possible
use strict;
use CPAN;

my $action = $ARGV[0] 
    or die "Missing required argument: action";

#DEPS is now a hash with the key being the actual perl module that must be installed, and the value being a space-delimited 
#list of apt-get packages that correspond to the perl module in some way (be it the actual module, or a dependency for the module)

my %DEPS = (
    'CGI 3.20' , '',
    'Ima::DBI 0.35' , 'libima-dbi-perl',
    'Class::DBI 3.0.10' , 'libclass-dbi-perl',
    'Class::DBI::AbstractSearch' , 'libclass-dbi-abstractsearch-perl',
    'Apache2::Request'  , 'libapache2-request-perl',
    'HTML::Mason 1.31' ,'libhtml-mason-perl',
    'Apache::Session 1.6' , 'libapache-session-perl',
    'URI::Escape' , 'liburi-perl',
    'DBIx::DataSource' , 'libdbix-datasource-perl',
    'GraphViz 2.02' , 'graphviz',
    'SQL::Translator 0.07' , 'libsql-translator-perl',
    'SNMP::Info 2.01' , 'libsnmp-info-perl',
    'NetAddr::IP' , 'libnetaddr-ip-perl',
    'Apache2::SiteControl 1.0' , '',
    'Log::Dispatch' , 'liblog-dispatch-perl',
    'Log::Log4perl' , 'liblog-log4perl-perl',
    'Parallel::ForkManager' , 'libparallel-forkmanager-perl',
    'Net::IPTrie' , '',
    'Authen::Radius' , 'libauthen-radius-perl',
    'RRDs' , 'librrds-perl',
    'Test::More' , '',
    'Test::Harness' , 'libtest-harness-perl',
    'Net::IRR', '',
    'Time::Local', 'libtime-local-perl',
    'File::Spec', 'libfile-spec-perl',
    'Net::Appliance::Session', '', 
    'BIND::Config::Parser', 'libbind-confparser-perl',
    'Net::DNS', 'libnet-dns-perl',
    'Text::ParseWords', '',
    'Carp::Assert', 'libcarp-assert-perl',
    'Digest::SHA', 'libdigest-sha-perl',
    'Net::DNS::ZoneFile::Fast 1.12', 'libnet-dns-sec-perl'
    ) ;

if ( $action eq 'test' ){
    run_test();
}

elsif ( $action eq 'install' || $action eq 'apt-get-install' ){
    
    my $uid = `id -u`;
    if($uid && $uid != 0){
        print "You must be root to install the required dependencies\n";
        exit(1);
    }
    
    if($action eq 'apt-get-install'){
        my $apt_arg_builder = "";

        foreach my $module (keys %DEPS){
            $apt_arg_builder .= " ".$DEPS{$module};
        }

        #now that we have a huge list of things to install via apt-get, lets run the command
        my $apt_results = system("apt-get -y install $apt_arg_builder");
        
        #error code for command not found
        if($apt_results > 1){
            if($apt_results == 127){
                print "It looks like we can't find apt-get,";
            }
            elsif($apt_results > 1){
		        print "Seems like there was a problem running apt-get,";
	        }
            print " would you like to continue and".
                " install all modules through CPAN [y/n]? [y] ";

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
    foreach my $module ( keys %DEPS ){
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
    foreach my $module ( keys %DEPS ){
	    eval "use $module";
	    print $module, "................";
	    if ( $@ ){
	        print "MISSING";
	    }
        else{
    	    print "installed"
	    }
	    print "\n";
    }
}

