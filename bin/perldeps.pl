#!/usr/bin/perl -w
#
# Facilitate dependencies installation

use strict;
use CPAN;

my $action = $ARGV[0] 
    or die "
Arguments:
	test              - Show list of installed and missing modules
	install           - Try to install missing modules using the CPAN
	apt-install       - Install using apt-get when possible
	rpm-install       - Install using rpm packages when possible
";

# DEPS is now a list of anonymous hashes with three keys 'cpan' 'apt' and 'rpm'.  
# Their contents should be fairly obvious, cpan is the name of the perl module in CPAN.  
# apt is the name or names (space delimited) of the perl module, 
# or perl modules that may be dependencies of the module in question
# if the module is not avaliable in the apt-get repository (installing dependencies 
# makes the cpan install process more reliable though).  rpm is the 
# same idea as apt, but refers to the module name in the rpm repository.

my @DEPS = (
    {apt=>'apache2', rpm=>'httpd'},
    {apt=>'libapache2-mod-perl2', rpm=>'mod_perl'},
    {apt=> 'rrdtool', rpm=>'rrdtool'},
    {cpan=>'RRDs' , apt=>'librrds-perl', rpm=>'rrdtool-perl'},
    {cpan=>'GraphViz', apt=> 'graphviz libgraphviz-perl', 
     rpm=>'graphviz graphviz-devel libpng-devel graphviz-gd perl-GraphViz'},
    {cpan=>'Module::Build' , apt=> 'libmodule-build-perl', rpm=>'perl-Module-Build'},
    {cpan=>'CGI' , apt=>'libcgi-pm-perl'},
    {cpan=>'Class::DBI', apt=> 'libclass-dbi-perl', rpm=>'perl-Class-DBI'},
    {cpan=>'Class::DBI::AbstractSearch', apt=>'libclass-dbi-abstractsearch-perl', 
     rpm=>'perl-Class-DBI-AbstractSearch'},
    {cpan=>'Apache2::Request', apt=>'libapache2-request-perl', 
     rpm=>'libapreq2 libapreq2-devel perl-libapreq2'},
    {cpan=>'HTML::Mason',apt=>'libhtml-mason-perl',rpm=>'perl-HTML-Mason'},
    {cpan=>'Apache::Session', apt=>'libapache-session-perl', rpm=>'perl-Apache-Session'},
    {cpan=>'URI::Escape', apt=>'liburi-perl', rpm=>'perl-URI'},
    {cpan=>'SQL::Translator', apt=>'libsql-translator-perl', rpm=>'perl-SQL-Translator'},
    {cpan=>'SNMP::Info 2.06', apt=>'libsnmp-info-perl', rpm=>'perl-SNMP-Info'},
    {apt=>'netdisco-mibs-installer'},
    {cpan=>'NetAddr::IP 4.042', apt=>'libnetaddr-ip-perl', rpm=>'perl-NetAddr-IP'},
    {cpan=>'Apache2::AuthCookie', apt=>'libapache2-authcookie-perl', rpm=>''},
    {cpan=>'Apache2::SiteControl', apt=>'libapache2-sitecontrol-perl', rpm=>''},
    {cpan=>'Log::Dispatch', apt=>'liblog-dispatch-perl', rpm=>'perl-Log-Dispatch'},
    {cpan=>'Log::Log4perl', apt=>'liblog-log4perl-perl', rpm=>'perl-Log-Log4perl'},
    {cpan=>'Parallel::ForkManager', apt=>'libparallel-forkmanager-perl', 
     rpm=>'perl-Parallel-ForkManager'},
    {cpan=>'Net::Patricia 1.20', apt=> 'libnet-patricia-perl', rpm=>''},
    {cpan=>'Authen::Radius', apt=>'libauthen-radius-perl', rpm=>'perl-Authen-Radius'},
    {cpan=>'Test::Simple' , apt=> 'libtest-simple-perl', rpm=>''},
    {cpan=>'Test::Exception' , apt=> 'libtest-exception-perl', rpm=>''},
    {cpan=>'Net::IRR', apt=> 'libnet-irr-perl', rpm=>''},
    {cpan=>'Time::Local', apt=> 'libtime-local-perl', rpm=>''},
    {cpan=>'File::Spec',apt=> 'libfile-spec-perl', rpm=>''},
    {cpan=>'Net::Appliance::Session',apt=> 'libnet-appliance-session-perl', rpm=>''},
    {cpan=>'BIND::Config::Parser', apt=>'libbind-config-parser-perl', rpm=>''},
    {cpan=>'Net::DNS', apt=> 'libnet-dns-perl', rpm=>'perl-Net-DNS'},
    {cpan=>'Text::ParseWords', apt=>'', rpm=>''},
    {cpan=>'Carp::Assert', apt=>'libcarp-assert-perl', rpm=>'perl-Carp-Assert'},
    {cpan=>'Digest::SHA', apt=> 'libdigest-sha-perl', rpm=>'perl-Digest-SHA1'},
    {apt=> 'libssl-dev', rpm=>'openssl-devel'}, # needed by Net::DNS::ZoneFile::Fast
    {cpan=>'Net::DNS::ZoneFile::Fast', apt=> 'dnssec-tools', rpm=>''},
    {cpan=>'Socket6', apt=> 'libsocket6-perl', rpm=>'perl-Socket6'},
    {cpan=>'XML::Simple', apt=>'libxml-simple-perl', rpm=>'perl-XML-Simple'},
    {apt=>'snmp'},
    ) ;

if ( $action eq 'test' ){
    &run_test();

}elsif ( $action eq 'install' || $action eq 'apt-install' || $action eq 'rpm-install'){

    # Needed for RPM installs
    my $epel_rel;
    my $installed_epel = 0;
    
    if ( $> != 0 ){
	die "You must be root to install required dependencies";
    }
    
    print "\nWhich RDBMS do you plan to use as backend: [mysql|Pg]? ";
    my $ans = <STDIN>;
    chomp($ans);
    if ( $ans =~ /mysql/i ){
	push (@DEPS, {apt=>'mysql-server', rpm=>'mysql-server'});
	push (@DEPS, {cpan=>'DBD::mysql', apt=> 'libdbd-mysql-perl', rpm=>'perl-DBD-MySQL'});

    }elsif ( $ans =~ /pg/i ){
	push (@DEPS, {apt=>'postgresql', rpm=>'postgresql'});
	push (@DEPS, {cpan=>'DBD::Pg', apt=> 'libdbd-pg-perl', rpm=>'perl-DBD-Pg'});
    }else{
	die "Unrecognized RDBMS: $ans\n";
    }
    my $program;
    if( $action eq 'rpm-install' ){
	$program = 'yum install';
	# Check if RHEL
	my $rhel_chk = `lsb_release -i`;
	if ( $rhel_chk =~ /RedHatEnterpriseServer/ ){
	    my $epel_chk = `rpm -qs epel-release`;
	    unless ( $epel_chk =~ /^normal/ ){
		print 'Be aware that the official RHEL repositories do not include many of the packages '.
		    'that Netdot requires.  Would you like to use the EPEL (Extra Packages for '.
		    'Enterprise Linux) repository to help install these packages? [y/n] ';
		my $ans = <STDIN>;
		if ( $ans =~ /(Y|y)/ ){
		    my $rh_rel = `lsb_release -r -s`;
		    chomp($rh_rel);
		    # Grab the first digit only
		    $rh_rel = int($rh_rel);
		    
		    # Set the current version of EPEL for this release
		    # TODO: find a way to automate this!
		    if ( $rh_rel eq '5' ){
			$epel_rel = '5-4';
		    }elsif ( $rh_rel eq '6' ){
			$epel_rel = '6-6';
		    }else{
			die "Unknown release: $rh_rel\n";
		    }
		    my $cmd = "rpm -Uvh http://mirrors.kernel.org/fedora-epel/$rh_rel/i386/".
			"epel-release-$epel_rel.noarch.rpm";
		    
		    &cmd($cmd);
		    $installed_epel = 1;
		    
		    # Check if optional channel is installed
		    my $rhel_optional_chk = `yum repolist`;
		    unless ( $rhel_optional_chk =~ /RHEL Server Optional/m ){
			print "It looks like this is RedHat Enterprise Server, but you have not \n".
			    "enabled the Optional channel, which is needed to satisfy dependencies \n".
			    "in the EPEL repository. See instructions at: \n\n".
			    "    https://access.redhat.com/knowledge/solutions/11312\n\n";
		    }
		}
	    }
	}
    }elsif ( $action eq 'apt-install' ){
	my $distro; # Can be Debian or Ubuntu
	my $debian_version; # Both Debian and Ubuntu have names for their versions
	print "\nWe need to add a temporary repository of Netdot dependencies ".
	    "until all packages are in Debian/Ubuntu official repositories.\n";
	print "Would you like to continue? [y/n] ";
	my $ans = <STDIN>;
	if ( $ans =~ /(Y|y)/ ){
	    my $apt_src_dir = '/etc/apt/sources.list.d';
	    $distro = `lsb_release -d`;
	    if ( $distro =~ /(debian)/io ){
		if ( $distro =~ /(squeeze)/io ){
		    $debian_version = lc($1);
		}
		$distro = 'debian';
	    }elsif ( $distro =~ /(ubuntu)/io ){
		$distro = 'ubuntu';
		$debian_version = `cat /etc/debian_version`;
		if ( $debian_version =~ /(wheezy)/io ){
		    $debian_version = lc($1);
		}
	    }
	    if ( -d $apt_src_dir ){
		my $file = "$apt_src_dir/netdot.apt.nsrc.org.list";
		open(FILE, ">$file")
		    or die "Cannot open $file for writing";
		my $str = "\n## Added by Netdot install\n".
		    "deb http://netdot.apt.nsrc.org/ unstable/\n".
		    "deb-src http://netdot.apt.nsrc.org/ unstable/\n\n";
		if ( $debian_version =~ /(wheezy|squeeze)/ ){
                    my $target = $1;	
		    $str .= "\n".
			"deb http://netdot.apt.nsrc.org/ $target/\n".
			"deb-src http://netdot.apt.nsrc.org/ $target/\n\n";
		}
		print FILE $str;
		close(FILE);
	    }else{
		die "Cannot find APT sources directory\n";
	    }
	    print "Updating package indexes from sources\n";
	    &cmd('apt-get update');
	}

	# The packages in our temporary repository will fail authentication
	# unless we use --force-yes
	$program = 'apt-get -y --force-yes install';
	
	# Try to install as little as possible
	$program .= ' --no-install-recommends';

	# libcrypt-cast5-perl is a requisite of libapache2-sitecontrol-perl
	# but it's architecture dependent, so we had to build specific packages
	# for these versions
	if ( $debian_version =~ /(wheezy|squeeze)/ ){
	    # Tell APT to pull the specific package
	    &cmd("$program -t $1 libcrypt-cast5-perl");
	}else{
	    # Package will come from Unstable. Might fail.
	    push (@DEPS, {apt=>'libcrypt-cast5-perl'});
	}
    }
    
    if ( $action eq 'apt-install' || $action eq 'rpm-install' ){
	my $argstr = " ";
	foreach my $anon_hash ( @DEPS ){
	    if ( $action eq 'apt-install' ){
		$argstr .= " ".$anon_hash->{'apt'} if exists $anon_hash->{'apt'};
	    }
	    else{
		$argstr .= " ".$anon_hash->{'rpm'} if exists $anon_hash->{'rpm'};
	    }
	}

	&cmd("$program $argstr");

    }elsif ( $action eq 'install' ){
	&install_modules_cpan();
    }

    if ( $installed_epel ){
	print "Would you like to uninstall EPEL at this time? [y/n] ";
	my $ans = <STDIN>;
	if ( $ans =~ /(Y|y)/ ){
	    &cmd("yum erase epel-release-$epel_rel.noarch");
	}
    }

    if ( $action eq 'apt-install' ){
	# Automate this part for the user too
	print "\nWe will install the MIB files now. Continue? [y/n] ";
	my $ans = <STDIN>;
	if ( $ans =~ /(Y|y)/ ){
	    print "Downloading necessary SNMP MIB files. This may take a few minutes.\n";
	    &cmd('rm -fr /tmp/netdisco-mibs');
	    &cmd('/usr/sbin/netdisco-mibs-download');
	    print "\nInstalling SNMP MIB files\n";
	    &cmd('/usr/sbin/netdisco-mibs-install');
	    print "\nA new /etc/snmp/snmp.conf needs to be installed to point to the newly ".
		"installed MIB files.\n";
	    print "The current file will be backed up. Continue? [y/n] ";
	    $ans = <STDIN>;
	    if ( $ans =~ /(Y|y)/ ){
		# We'll use the snmp.conf provided with netdisco-mibs. But it refers to
		# a different directory than the one used by netdisco-mibs-installer, so
		# we'll create a symlink
		unless ( -d '/usr/local/netdisco' ){
		    # Create directory for link
		    mkdir('/usr/local/netdisco');
		}
		unless ( -l '/usr/local/netdisco/mibs' ){
		    &cmd('ln -s /usr/share/netdisco/mibs /usr/local/netdisco/mibs');
		}
		&cmd('mv -f /etc/snmp/snmp.conf /etc/snmp/snmp.conf.netdot_install');
		&cmd('cp /usr/share/doc/netdisco-mibs-installer/contrib/snmp.conf /etc/snmp/snmp.conf');
		print("\nDone with snmp.conf\n");
	    }
	}
    }

    # Finally, lets call run_test to show the user if anything is missing
    print "\n===============RESULTS===============\n";
    &run_test();

    unless ( $action eq 'install' ){
	print "\nIf there are still any missing Perl modules, you can try:\n\n";
	print "    make installdeps\n\n"; 
    }

}

sub install_modules_cpan{

    $CPAN::Config->{prerequisites_policy}          = 'follow';
    $CPAN::Config->{ftp_passive}                   = '1';
    $CPAN::Config->{build_requires_install_policy} = 'yes';
    
    foreach my $anon_hash (@DEPS){
	my $module = $anon_hash->{'cpan'};
	next unless $module;

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
	my $module = $anon_hash->{'cpan'} if exists $anon_hash->{'cpan'};
	next unless $module;
	eval "use $module";
	my $len = 50 - length($module);
	my $sep = '.' x $len;
	print $module."$sep";
	if ( $@ ){
	    print "MISSING";
	}
	else{
	    print "ok";
	}
	print "\n";
    }
}

# Run system commands
sub cmd {
    my $str = shift;
    if ( system($str) != 0 ){
	die "There was a problem running $str\n";
    }
}
