package Netdot::Exporter::Smokeping;

use base 'Netdot::Exporter';
use warnings;
use strict;
use Data::Dumper;
use Carp;

my $logger = Netdot->log->get_logger('Netdot::Exporter');

=head1 NAME

Netdot::Exporter::Smokeping - Read relevant info from Netdot and build Smokeping configuration

=head1 SYNOPSIS

    my $smokeping = Netdot::Exporter->new(type=>'Smokeping');
    $smokeping->generate_configs()

=head1 CLASS METHODS
=cut

############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Exporter::Smokeping object
  Examples:
    my $smokeping = Netdot::Exporter->new(type=>'Smokeping');
=cut
sub new{
    my ($class, %argv) = @_;
    my $self = {};

    foreach my $key ( qw /SMOKEPING_DIR SMOKEPING_FILE/ ){
	$self->{$key} = Netdot->config->get($key);
    }
     
    bless $self, $class;
    return $self;
}

############################################################################
=head2 generate_configs - Generate configuration files for SMOKEPING

  Arguments:
    None
  Returns:
    True if successful
  Examples:
    $smokeping->generate_configs();
=cut
sub generate_configs {
    my ($self) = @_;

    my $query = $self->{_dbh}->selectall_arrayref("
                SELECT     rr.name, zone.name, p.name, e.name,
                           d.monitored, t.name, d.down_from, d.down_until
                 FROM      device d, rr, zone, product p, entity e, asset a,
                           producttype t, ipblock i
                WHERE      d.name=rr.id
                  AND      rr.zone=zone.id
                  AND      a.product_id=p.id
                  AND      d.asset_id=a.id
                  AND      p.manufacturer=e.id
                  AND      p.type = t.id
         ");
    
    my %types;
    foreach my $row ( @$query ){
	my ($rrname, $zone, $product, $vendor,
	    $monitor, $type, $down_from, $down_until) = @$row;  

	my $name = $rrname . "." . $zone;
	$type =~ s/\s+//;

	unless ( $monitor ){
	    $logger->debug("Netdot::Exporter::Smokeping::generate_configs: ".
			   "$name configured to not monitor config");
	    next;
	}

	unless ( $type ){
	    $logger->warn("Netdot::Exporter::Smokeping::generate_configs: $name has no Type!");
	    next;
	}

        # Check maintenance dates to see if this device should be excluded
	if ( $down_from && $down_until && 
	     $down_from ne '0000-00-00' && $down_until ne '0000-00-00' ){
	    my $time1 = Netdot::Model->sqldate2time($down_from);
	    my $time2 = Netdot::Model->sqldate2time($down_until);
	    my $now = time;
	    if ( $time1 < $now && $now < $time2 ){
		$logger->debug("Netdot::Exporter::Smokeping::generate_configs: $name in down time.");
		next;
	    }
	}
        $types{$type}{$name}{rrname} = $rrname;
    }

    foreach my $type ( keys %types ){
	my $dir_path  = $self->{SMOKEPING_DIR}."/".$type;
	unless ( -d $dir_path ){
	    system("mkdir -p $dir_path") 
		&& $self->throw_user("Netdot::Exporter::Smokeping::generate_configs: ".
				      "Can't make dir $dir_path: $!");
	}
	my $file_path = "$dir_path/".$self->{SMOKEPING_FILE};
	my $smokeping = $self->open_and_lock($file_path);
	print $smokeping "
################################################
#
# Automatically generated from Netdot
# Do not edit - contents will be overwritten
#
################################################

+ $type
  
menu = $type Connectivity
title = $type Connectivity
alerts = 

";
	foreach my $device ( sort keys %{$types{$type}} ){
	    my $rrname = $types{$type}{$device}{rrname};
	    print $smokeping "++ $rrname
menu = $rrname
title = $device
host = $device
  
";
	}
        print $smokeping "# End of file\n";
	close($smokeping) || $logger->warn("Netdot::Exporter::Smokeping::generate_configs: ".
					   "$file_path did not close nicely");
	
	$logger->info("Netdot::Exporter::Smokeping::generate_configs:".
		      " Smokeping configuration for group '$type' written to: '$file_path'");
    }
}

=head1 AUTHOR

Andy Linton and Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

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
