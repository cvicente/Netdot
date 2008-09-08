package Netdot::Exporter::Sysmon;

use base 'Netdot::Exporter';
use warnings;
use strict;
use Data::Dumper;
use Carp;

my $logger = Netdot->log->get_logger('Netdot::Exporter');

=head1 NAME

Netdot::Exporter::Sysmon - Read relevant info from Netdot and build Sysmon configuration

=head1 SYNOPSIS

    my $sysmon = Netdot::Exporter->new(type=>'Sysmon');
    $sysmon->generate_configs()

=head1 CLASS METHODS
=cut

############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Exporter::Sysmon object
  Examples:
    my $sysmon = Netdot::Exporter->new(type=>'Sysmon');
=cut

sub new{
    my ($class, %argv) = @_;
    my $self = {};

    foreach my $key ( qw /NMS_DEVICE SYSMON_DIR SYSMON_FILE SYSMON_QUEUETIME SYSMON_MAXQUEUED 
                          SYSMON_HTML_FILE SYSMON_HTML_REFRESH SYSMON_LOG_FACILITY SYSMON_STRIP_DOMAIN/ ){
	$self->{$key} = Netdot->config->get($key);
    }
     
    defined $self->{NMS_DEVICE} ||
	croak "Netdot::Exporter::Sysmon: NMS_DEVICE not defined";

    $self->{MONITOR} = Device->search(name=>$self->{NMS_DEVICE})->first 
	|| croak "Netdot::Exporter::Sysmon: Monitoring device not found in DB: " . $self->{NMS_DEVICE};
    
    bless $self, $class;
    return $self;
}

############################################################################
=head2 generate_configs - Generate configuration files for Sysmon

  Arguments:
    None
  Returns:
    True if successful
  Examples:
    $sysmon->generate_configs();
=cut
sub generate_configs {
    my ($self) = @_;

    my (%hosts, %ip2name);

    my $device_ips = $self->get_monitored_ips();
    my $monitor      = $self->{MONITOR};
    my $dependencies = $self->get_dependencies($monitor->id);

    foreach my $row ( @$device_ips ){
	my ($deviceid, $ipid, $address, $hostname) = @$row;

 	if ( $self->{SYSMON_STRIP_DOMAIN} ){
 	    my $domain = Netdot->config->get('DEFAULT_DNSDOMAIN');
 	    $hostname =~ s/\.$domain}//;
 	}

	$hosts{$ipid}{name} = $hostname;
	$ip2name{$ipid}     = $hostname;
    }

    # Now that we have everybody in
    # assign parent list
    foreach my $ipid ( keys %hosts ){
	next unless defined $dependencies->{$ipid};
	if ( my @parentlist = @{$dependencies->{$ipid}} ){
	    my @names;
	    foreach my $parent ( @parentlist ){
		if ( !exists $ip2name{$parent} ){
		    $logger->warn("IP $ipid parent $parent not in monitored list."
				  ." Skipping.");
		    next;
		}
		push @names, $ip2name{$parent};
	    }
	    $hosts{$ipid}{parents} = \@names;
	}else{
	    $hosts{$ipid}{parents} = undef;
	}
    }
    
    # Open output file for writing
    my $filename = $self->{SYSMON_DIR}."/".$self->{SYSMON_FILE};
    open (SYSMON, ">$filename") 
	or die "Can't open $filename $!\n";
    
    my $root = $self->{MONITOR}->fqdn();
    print SYSMON <<EOP;
root \"$root\"\;
config queuetime $self->{SYSMON_QUEUETIME}\;
config maxqueued $self->{SYSMON_MAXQUEUED}\;
config noheartbeat\;
config logging syslog \"$self->{SYSMON_LOG_FACILITY}\"\;
config statusfile html \"$self->{SYSMON_HTML_FILE}\"\;
config html refresh $self->{SYSMON_HTML_REFRESH};
EOP

    
    foreach my $ipid ( sort { $hosts{$a}{name} cmp $hosts{$b}{name} } keys %hosts ){
	my $name = $hosts{$ipid}{name};
	
	print SYSMON "\n";
	print SYSMON "object $name \{\n";
	print SYSMON "   ip \"$name\"\;\n";
	print SYSMON "   type ping\;\n";
	print SYSMON "   desc \"$name\"\;\n";
	
	foreach my $parent ( @{ $hosts{$ipid}{parents} } ){
	    next if ($parent eq "");
	    print SYSMON "   dep \"$parent\"\;\n";
	}
	
	print SYSMON "\}\;";
	print SYSMON "\n";
	
    }
    
    close(SYSMON) or $logger->warn("$filename did not close nicely");
    $logger->info("Sysmon configuration written to $filename");
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 University of Oregon, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut

#Be sure to return 1
1;
