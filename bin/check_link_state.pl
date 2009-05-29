#!/usr/bin/perl -w
use SNMP::Info;
use strict;
use Data::Dumper;
use lib "<<Make:LIB>>";
use Netdot::Model;
#
#
# This simple utility collects interface status from devices matching a
# given regular expression, and prints a report containing interfaces that 
# are operationally down and administratively up.  It can be run periodically
# as a CRON job.
#
my $DEBUG = 0;
my %down_ports;
my $name_regex = $ARGV[0] || 
    die "Usage: $0 <device name regex>\n";

foreach my $d ( Device->retrieve_all() ){
    if ( $d->get_label =~ /$name_regex/ ){
	if ( $d->snmp_managed ){
	    &debug("Connecting to ".$d->get_label);
	    my $info;
	    eval {
		$info = $d->_get_snmp_session();
	    };
	    if ( my $e = $@ ){
		warn "$e\n";
	    }else{
		&check_ports($info, $d) if $info;
	    }
	}
    }
}

&print_report() if %down_ports;


######################################################################################
# Subroutines
######################################################################################


######################################################################################
sub print_report{
    print "\n";
    print "The Following ports are administratively up, but operationally down: \n\n";
    foreach my $n ( sort keys %down_ports ){
	print $n, "\n";
	foreach my $p ( sort { $a <=> $b } keys %{$down_ports{$n}} ){
	    print "    $p $down_ports{$n}{$p}{name}";
	    print " ($down_ports{$n}{$p}{description})" if $down_ports{$n}{$p}{description};
	    print "\n";
	}
	print "\n";
    }
}

######################################################################################
sub check_ports {
    my ($info, $d) = @_;
    my $interfaces   = $info->interfaces();
    my $oper_status  = $info->i_up();
    my $admin_status = $info->i_up_admin();
    my $names        = $info->i_description();
    my $descriptions = $info->i_alias();
    
    foreach my $iid ( sort { $a <=> $b } keys %$interfaces ){
	&debug($d->get_label . ": Checking interface: $iid");
	if ( $d->monitored && 
	     defined $admin_status->{$iid} && 
	     defined $oper_status->{$iid} ){
	    
	    if ( $admin_status->{$iid} eq 'up' &&
		 $oper_status->{$iid}  eq 'down' ){
		$down_ports{$d->fqdn}{$iid}{name}        = $names->{$iid};
		$down_ports{$d->fqdn}{$iid}{description} = $descriptions->{$iid};
	    }
	}
    }
}

sub debug{
    print @_, "\n" if $DEBUG;
}
