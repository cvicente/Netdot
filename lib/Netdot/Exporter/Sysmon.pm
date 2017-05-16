package Netdot::Exporter::Sysmon;

use base 'Netdot::Exporter';
use warnings;
use strict;
use Data::Dumper;

my $logger = Netdot->log->get_logger('Netdot::Exporter');

=head1 NAME

Netdot::Exporter::Sysmon

=head1 DESCRIPTION

    Read relevant info from Netdot and build Sysmon configuration

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
	$self->{$key} = (exists $argv{$key})? $argv{$key} : Netdot->config->get($key);
    }
     
    defined $self->{NMS_DEVICE} ||
	$self->throw_user("Netdot::Exporter::Sysmon: NMS_DEVICE not defined");

    $self->{ROOT} = Device->search(name=>$self->{NMS_DEVICE})->first 
	|| $self->throw_user("Netdot::Exporter::Sysmon: Monitoring device not found in DB: " . 
			     $self->{NMS_DEVICE});
    
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

    my (%hosts, %names);

    my $device_info    = $self->get_device_info();
    my $root           = $self->{ROOT};
    my $device_parents = $self->get_device_parents($root->id);

    foreach my $devid ( keys %$device_info ){

	# Is it within downtime period?
	my $monitored = (!$self->in_downtime($devid))? 1 : 0;
	next unless $monitored;

	my $hostname = $device_info->{$devid}->{hostname} || next;
	$hostname = $self->strip_domain($hostname);
	$hosts{$devid}{name} = $hostname;
	
	if ( !exists $names{$hostname} && Netdot->dns->resolve_name($hostname) ){
	    $hosts{$devid}{ip} = $hostname;
	    $names{$hostname} = 1;
	}else{
	    $logger->warn("$hostname does not resolve, or duplicate. Using IP.");
	    # Determine IP
	    my $devh = $device_info->{$devid};
	    unless $devh->{target_addr} && $devh->{target_version}{
		$logger->warn("Cannot determine IP address for $hostname. Skipping");
		delete $hosts{$devid};
		next;
	    }
	    my $ip = Ipblock->int2ip($devh->{target_addr}, $devh->{target_version});
	    $hosts{$devid}{ip} = $ip;
	}
	
	foreach my $parent_id ( $self->get_monitored_ancestors($devid, $device_parents) ){
	    my $hostname = $device_info->{$parent_id}->{hostname};
	    $hostname = $self->strip_domain($hostname);
	    push @{$hosts{$devid}{parents}}, $hostname;
	}
    }

    
    # Open output file for writing
    my $filename = $self->{SYSMON_DIR}."/".$self->{SYSMON_FILE};
    my $sysmon = $self->open_and_lock($filename);
    
    my $root_name = $root->fqdn();
    $root_name = $self->strip_domain($root_name);

    print $sysmon <<EOP;
root \"$root_name\"\;
config queuetime $self->{SYSMON_QUEUETIME}\;
config maxqueued $self->{SYSMON_MAXQUEUED}\;
config noheartbeat\;
config logging syslog \"$self->{SYSMON_LOG_FACILITY}\"\;
config statusfile html \"$self->{SYSMON_HTML_FILE}\"\;
config html refresh $self->{SYSMON_HTML_REFRESH};
EOP

    
    foreach my $devid ( sort { $hosts{$a}{name} cmp $hosts{$b}{name} } keys %hosts ){
	my $name = $hosts{$devid}{name};
	my $ip   = $hosts{$devid}{ip};
	print $sysmon "\n";
	print $sysmon "object $name \{\n";
	print $sysmon "   ip \"$ip\"\;\n";
	print $sysmon "   type ping\;\n";
	print $sysmon "   desc \"$name\"\;\n";
	
	if ( exists $hosts{$devid}{parents} && @{$hosts{$devid}{parents}} ){
	    foreach my $parent ( @{ $hosts{$devid}{parents} } ){
		next if ($parent eq "");
		print $sysmon "   dep \"$parent\"\;\n";
	    }
	}else{
	    print $sysmon "   dep \"$root_name\"\;\n";
	}
	print $sysmon "\}\;";
	print $sysmon "\n";
	
    }

    $self->print_eof($sysmon);
    close($sysmon) or $logger->warn("$filename did not close nicely");
    $logger->info("Sysmon configuration written to $filename");
}

########################################################################

=head2 strip_domain - Strip domain name from hostname if necessary

  Arguments:
    hostname string
  Returns:
    string
  Examples:
    
=cut

sub strip_domain {
    my ($self, $hostname) = @_;

    return unless $hostname;
    if ( Netdot->config->get('SYSMON_STRIP_DOMAIN') ){
	my $domain = Netdot->config->get('DEFAULT_DNSDOMAIN');
	$hostname =~ s/\.$domain// ;
    }
    return $hostname;
}


=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 University of Oregon, all rights reserved.

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
