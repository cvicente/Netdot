package Netdot::Model::Topology;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

# Make sure to return 1
1;

=head1 NAME

Netdot::Model::Topology

=head1 SYNOPSIS

Netdot Device Topology Class

=head1 CLASS METHODS
=cut

=head2 discover - Discover Topology
        
  Arguments:
    Hash with following keys:
    ipblock - CIDR block (192.168.0.0/24)
  Returns:
    
  Examples:


=cut
######################################################################################
sub discover {
    my ($class, %argv) = @_;
    $class->isa_class_method('discover');

    if ( $argv{ipblock} ){
	my $ip = Ipblock->search(address=>$argv{ipblock})->first;
	unless ( $ip ){
	    $class->throw_user("IP block $argv{ipblock} not found in DB");
	}
	if ( $ip->status->name eq 'Container' ){
	    $logger->info(sprintf("Performing topology discovery on IP Block %s", $ip->get_label));
	    # Get all possible subnets
	    my @subnets = Ipblock->search(parent=>$ip, status=>'Subnet');
	    foreach my $s ( @subnets ){
		$class->discover_subnet($s);
	    }
	}elsif ( $ip->status->name eq 'Subnet' ){
	    $class->discover_subnet($ip);
	}else{
	    $class->throw_user(sprintf("Block %s is a %s. Topology discovery only allowed on Container or Subnet Blocks",
				       $ip->get_label, $ip->status->name ));
	}
    }
}

=head2 
    
    
  Arguments:

  Returns:

  Examples:


=cut
######################################################################################
sub discover_subnet{
    my ($class, $subnet) = @_;
    $class->isa_class_method('discover_subnet');
    
    $logger->info(sprintf("Performing topology discovery on Subnet %s", $subnet->get_label));

    # STP sources
    if ( my $vlan = $subnet->vlan ){
	my $stp_links = $vlan->get_stp_links();
	if ( $stp_links ){
	    $class->add_neighbors($stp_links);
	}
    }
}

=head2 
    
    
  Arguments:

  Returns:

  Examples:


=cut
######################################################################################
sub add_neighbors {
    my ($class, $links) = @_;

    foreach my $id ( keys %$links ){
	my $int = Interface->retrieve($id) || $class->throw_fatal("Cannot retrieve Interface id $id");
	my $neighbor = Interface->retrieve($links->{$id}) || $class->throw_fatal("Cannot retrieve Interface id $links->{$id}");
	
	if ( int($int->neighbor) && int($neighbor->neighbor) && 
	     $int->neighbor->id == $neighbor->id && $neighbor->neighbor->id == $int->id ){
	    next;
	}else{
	    $logger->info(sprintf("Adding new neighbors: %s <=> %s", 
				  $int->get_label, $neighbor->get_label));
	    if ( $int->neighbor && $int->neighbor_fixed ){
		$logger->warn(sprintf("%s has been manually fixed to %s", $int->get_label, 
				      $int->neighbor->get_label));
	    }elsif ( $neighbor->neighbor && $neighbor->neighbor_fixed ) {
		$logger->warn(sprintf("%s has been manually fixed to %s", $neighbor->get_label, 
				      $neighbor->neighbor->get_label));
	    }else{
		$int->update({neighbor=>$neighbor});
	    }
	}
    }
}
