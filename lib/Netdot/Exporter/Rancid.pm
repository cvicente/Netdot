package Netdot::Exporter::Rancid;

use base 'Netdot::Exporter';
use warnings;
use strict;
use Data::Dumper;
use Carp;

my $logger = Netdot->log->get_logger('Netdot::Exporter');

=head1 NAME

Netdot::Exporter::Rancid - Read relevant info from Netdot and build Rancid configuration

=head1 SYNOPSIS

    my $rancid = Netdot::Exporter->new(type=>'Rancid');
    $rancid->generate_configs()

=head1 CLASS METHODS
=cut

############################################################################

=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Exporter::Rancid object
  Examples:
    my $rancid = Netdot::Exporter->new(type=>'Rancid');
=cut

sub new{
    my ($class, %argv) = @_;
    my $self = {};

    foreach my $key ( qw /RANCID_DIR RANCID_FILE/ ){
	$self->{$key} = Netdot->config->get($key);
    }
     
    $self->{MFG_MAP} = Netdot->config->get('RANCID_TYPE_MAP');

    $self->{EXCLUDE} = Netdot->config->get('RANCID_EXCLUDE') || {};
    
    bless $self, $class;
    return $self;
}

############################################################################

=head2 generate_configs - Generate configuration files for RANCID

  Arguments:
    None
  Returns:
    True if successful
  Examples:
    $rancid->generate_configs();
=cut

sub generate_configs {
    my ($self) = @_;

    my $dbh = Netdot::Model->db_Main();

    my $query = $dbh->selectall_arrayref("
          SELECT rr.name, zone.name, p.name, p.sysobjectid, p.config_type, e.name, e.config_type,
                 d.sysdescription, d.monitor_config, d.monitor_config_group, d.down_from, d.down_until
          FROM   device d, rr, zone, product p, entity e, asset a
          WHERE  d.name=rr.id
          AND    rr.zone=zone.id
          AND    a.product_id=p.id
          AND    d.asset_id=a.id
          AND    p.manufacturer=e.id
         ");
    
    my %groups;
    foreach my $row ( @$query ){
	my ($rrname, $zone, $product, $oid, $p_ctype, $vendor, $v_ctype, 
	    $sysdescr, $monitor, $group, $down_from, $down_until) = @$row;  

	my $name = $rrname . "." . $zone;

	unless ( $monitor ){
	    $logger->debug("Netdot::Exporter::Rancid::generate_configs: $name configured ".
			   "to not monitor config");
	    next;
	}

	unless ( $group ){
	    $logger->warn("Netdot::Exporter::Rancid::generate_configs: $name has no Config Group!");
	    next;
	}

	if ( defined $oid && exists $self->{EXCLUDE}->{$oid} ){
	    my $descr = $self->{EXCLUDE}->{$oid};
	    $logger->debug("Netdot::Exporter::Rancid::generate_configs: $name: $descr ($oid) ".
			   "excluded per configuration");
	    next;
	}
	
	# Check maintenance dates to see if this device should be excluded
	$groups{$group}{$name}{state} = 'up';
	if ( $down_from && $down_until && 
	     $down_from ne '0000-00-00' && $down_until ne '0000-00-00' ){
	    my $time1 = Netdot::Model->sqldate2time($down_from);
	    my $time2 = Netdot::Model->sqldate2time($down_until);
	    my $now = time;
	    if ( $time1 < $now && $now < $time2 ){
		$logger->debug("Netdot::Exporter::Rancid::generate_configs: $name in down time. ".
			       "Setting state to 'down'.");
		$groups{$group}{$name}{state} = 'down';
	    }
	}

	my $mfg = $self->_convert_mfg(vendor   => $vendor, 
				      v_ctype  => $v_ctype, 
				      p_ctype  => $p_ctype,
				      sysdescr => $sysdescr,
	    );
	unless ( $mfg ) {
	    $logger->debug("Netdot::Exporter::Rancid::generate_configs: $name: $vendor has no ".
			   "RANCID device_type mapping");
	    next;
	}
	$groups{$group}{$name}{mfg} = $mfg;
    }

    foreach my $group ( keys %groups ){
	my $dir_path  = $self->{RANCID_DIR}."/".$group;
	unless ( -d $dir_path ){
	    system("mkdir -p $dir_path") 
		&& $self->throw_fatal("Netdot::Exporter::Rancid::generate_configs: Cannot make dir ".
				      "$dir_path: $!");
	}
	my $file_path = "$dir_path/".$self->{RANCID_FILE};
	my $rancid = $self->open_and_lock($file_path);

	foreach my $device ( sort keys %{$groups{$group}} ){
	    my $mfg   = $groups{$group}{$device}{mfg} || next;
	    my $state = $groups{$group}{$device}{state} || next;
	    my $delim = Netdot->config->get('RANCID_DELIM');
	    $self->throw_user(sprintf("Netdot::Exporter::Rancid::generate_configs: ".
				      "Invalid Rancid delimiter: '%s'", $delim)) 
		unless ($delim eq ';' || $delim eq ':');
	    my $str = join($delim, ($device, $mfg, $state));
	    print $rancid "$str\n";
	}
	close($rancid) || $logger->warn("Netdot::Exporter::Rancid::generate_configs: ".
				    "$file_path did not close nicely");

	$logger->info("Netdot::Exporter::Rancid::generate_configs:".
		      " Rancid configuration for group '$group' written to: '$dir_path'");
    }
}



############################################################################
# Choose the RANCID device type

sub _convert_mfg {
    my ($self, %argv) = @_;
    my ($vendor, $v_ctype, $p_ctype, $sysdescr) = 
	@argv{'vendor', 'v_ctype', 'p_ctype', 'sysdescr'};

    return unless $vendor;

    my $mfg;
    if ( $p_ctype ){
	$mfg = $p_ctype;
    }elsif ( $v_ctype ){
	$mfg = $v_ctype;
    }else{
	foreach my $key ( keys %{$self->{MFG_MAP}} ){
	    if ( $vendor =~ /$key/i ){
		$mfg = $self->{MFG_MAP}{$key};
		last;
	    }
	}
    }
    # More granularity for some vendors
    if ( defined($mfg) && $mfg eq 'cisco' ){
	if ( $sysdescr && $sysdescr =~ /NX-OS/o ){
	    $mfg = 'cisco-nx';
	}
    }
    return $mfg;
}
  
=head1 AUTHORS

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

1;
