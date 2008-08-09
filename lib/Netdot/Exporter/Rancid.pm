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
     
    # Convert these Netdot Manufacturer names into RANCID's known types
    # See RANCID documentation for list of available device types
    $self->{MFG_MAP} = {
	'cisco'      => 'cisco',
	'enterasys'  => 'enterasys',
	'extreme'    => 'extreme',
	'force10'    => 'force10',
	'foundry'    => 'foundry',
	'Hewlett|HP' => 'hp',
	'juniper'    => 'juniper',
	'netscreen'  => 'netscreen',
    };
    
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

    my $query = $self->{_dbh}->selectall_arrayref("
                SELECT     rr.name, zone.mname, p.name, p.sysobjectid, e.name,
                           d.monitor_config, d.monitor_config_group
                 FROM      device d, rr, zone, product p, entity e
                WHERE      d.name=rr.id
                  AND      rr.zone=zone.id
                  AND      d.product=p.id
                  AND      p.manufacturer=e.id
         ");
    
    my %groups;
    foreach my $row ( @$query ){
	my ($rrname, $zone, $product, $oid, $vendor,
	    $monitor, $group) = @$row;  
	
	my $name = $rrname . "." . $zone;
	unless ( $monitor ){
	    $logger->debug("Netdot::Exporter::Rancid:generate_configs: $name configured to not monitor config");
	    next;
	}
	if ( exists $self->{EXCLUDE}->{$oid} ){
	    my $descr = $self->{EXCLUDE}->{$oid};
	    $logger->debug("$name: $descr ($oid) excluded in configuration");
	    next;
	}
	
	my $mfg = $self->_convert_mfg($vendor);
	unless ( $mfg ) {
	    $logger->debug("Netdot::Exporter::Rancid:generate_configs: $vendor has no RANCID device_type mapping");
	    next;
	}
	$groups{$group}{$name}{mfg} = $mfg;
    }

    foreach my $group ( keys %groups ){
	my $dir_path  = $self->{RANCID_DIR}."/".$group;
	unless ( -d $dir_path ){
	    system("mkdir -p $dir_path") 
		&& $self->throw_fatal("Netdot::Exporter::Rancid:generate_configs: Can't make dir $dir_path: $!");
	}
	my $file_path = "$dir_path/".$self->{RANCID_FILE};
	open (RANCID, ">$file_path")
	    or $self->throw_fatal("Netdot::Exporter::Rancid:generate_configs: Can't open $file_path: $!");

	foreach my $device ( sort keys %{$groups{$group}} ){
	    my $mfg = $groups{$group}{$device}{mfg};
	    print RANCID $device, ":$mfg:up\n";
	}
	close(RANCID) || $logger->warn("Netdot::Exporter::Rancid:generate_configs: ".
				    "$file_path did not close nicely");

	$logger->info("Netdot::Exporter::Rancid:generate_configs:".
		      " Rancid configuration for group '$group' written to: '$dir_path'");
    }
}



############################################################################
sub _convert_mfg {
    my ($self, $vendor) = @_;
    return unless $vendor;
    foreach my $key ( keys %{$self->{MFG_MAP}} ){
	if ( $vendor =~ /$key/i ){
	    return $self->{MFG_MAP}{$key};
	}
    }
}
