package Netdot::Exporter::BIND;

use base 'Netdot::Exporter';
use warnings;
use strict;
use Data::Dumper;

my $logger = Netdot->log->get_logger('Netdot::Exporter');

=head1 NAME

Netdot::Exporter::BIND - Read relevant info from Netdot and build BIND zone files

=head1 SYNOPSIS

    my $bind = Netdot::Exporter->new(type=>'BIND');
    $bind->generate_configs()

=head1 CLASS METHODS
=cut

############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Exporter::BIND object
  Examples:
    my $bind = Netdot::Exporter->new(type=>'BIND');
=cut

sub new{
    my ($class, %argv) = @_;
    my $self = {};

    bless $self, $class;
    return $self;
}

############################################################################
=head2 generate_configs - Generate zone files for BIND

  Arguments:
    Hashref with the following keys:
      zones  - Array ref.  List of zone names to export.
      nopriv - Exclude private data from zone file (TXT and HINFO)
  Returns:
    True if successful
  Examples:
    $bind->generate_configs();
=cut
sub generate_configs {
    my ($self, %argv) = @_;
    
    my @zones;
    
    if ( $argv{zones} ){
	unless ( ref($argv{zones}) eq 'ARRAY' ){
	    $self->throw_fatal("zones argument must be arrayref!");
	}
	foreach my $name ( @{$argv{zones}} ){
	    if ( Zone->search(name=>$name) ){
		push @zones, Zone->search(name=>$name)->first;
	    }else{
		$self->throw_user("Zone $name not found");
	    }
	}
    }elsif ( $argv{zone_ids} ){
	unless ( ref($argv{zone_ids}) eq 'ARRAY' ){
	    $self->throw_fatal("zone_ids argument must be arrayref!");
	}
	foreach my $id ( @{$argv{zone_ids}} ){
	    if ( my $zone = Zone->retrieve($id) ){
		push @zones, $zone;
	    }else{
		$self->throw_user("Zone $id not found");
	    }
	}

    }else{
	@zones = Zone->retrieve_all();
    }
    
    foreach my $zone ( @zones ){
	if ( $zone->audit_records() || $argv{force} ){
	    if ( $zone->active ){
		my $path = $self->print_zone_to_file(zone=>$zone, nopriv=>$argv{nopriv});
		$logger->info("Zone ".$zone->name." written to file: $path");
	    }
	    
	    # Flush audit records for this zone
	    map { $_->delete } $zone->audit_records;

	}else{
	    $logger->debug($zone->name.": No pending changes.  Use -f to force.");
	}
    }
}

############################################################################
=head2 print_zone_to_file -  Print the zone file using BIND syntax

 Args: 
    Hashref with following key/value pairs:
        zone    - Zone object
        nopriv  - Flag.  Exclude private data (TXT and HINFO)
  Returns: 
    Path of file written to
  Examples:
    my $path = $bind->print_to_file(zone=>$zone, nopriv=>1);

=cut
sub print_zone_to_file {
    my ($self, %argv) = @_;

    my $zone = $argv{zone};

    $self->throw_fatal("Missing required argument: zone")
	unless $zone;

    my $rec = $zone->get_all_records();

    my $dir = Netdot->config->get('BIND_EXPORT_DIR') 
	|| $self->throw_user('BIND_EXPORT_DIR not defined in config file!');
    
    my $filename = $zone->export_file;
    unless ( $filename ){
	$logger->warn('Export filename not defined for this zone: '. $zone->name.' Using zone name.');
	$filename = $zone->name;
    }
    my $path = "$dir/$filename";
    my $fh = $self->open_and_lock($path);
    $zone->_update_serial();

    # Print the default TTL
    print $fh '$TTL '.$zone->default_ttl."\n" if (defined $zone->default_ttl);

    # Print the SOA record
    print $fh $zone->soa_string . "\n";
    
    foreach my $name ( sort {$a cmp $b} keys %$rec ){
	foreach my $type ( qw/A AAAA TXT HINFO NS MX CNAME PTR NAPTR SRV LOC/ ){
	    if ( defined $rec->{$name}->{$type} ){
		# Special cases.  These are relatively rare and hard to print.
		if ( $type =~ /(LOC|SRV|NAPTR)/ ){
		    my $rrclass = 'RR'.$type;
		    my $id = $rec->{$name}->{$type}->{id};
		    my $rr = $rrclass->retrieve($id);
		    print $fh $rr->as_text, "\n";
		}else{
		    next if ( $type =~ /(HINFO|TXT)/ && $argv{nopriv} );
		    foreach my $data ( keys %{$rec->{$name}->{$type}} ){
			my $ttl = $rec->{$name}->{$type}->{$data};
			if ( !defined $ttl || $ttl !~ /\d+/ ){
			    $logger->debug("$name $type: TTL not defined or invalid. Using Zone default");
			    $ttl = $zone->default_ttl;
			}
			print $fh "$name\t$ttl\tIN\t$type\t$data\n";
		    }
		}
	    }
	}
    }
    close($fh);
    return $path;
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>
Dongting Yu, C<< <dongting at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 University of Oregon, all rights reserved.

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
