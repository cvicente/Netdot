package Netdot::Model::Product;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

# Make sure to return 1
1;

=head1 NAME

Netdot::Model::Product - Netdot Device Product Class

=head1 SYNOPSIS

    
    use Netdot::Model::Product;

    my $product = Product->insert(%args);

    ...

=head1 CLASS METHODS

=cut

############################################################################
=head2 insert - Insert product

    Override parent method to:
    - Use sysobectid value to determine manufacturer
    - Use part_number or sysobjectid as name if needed

  Arguments:  
     (in addition to Product's columns)
     hostname - (optional) for guessing product type based on device name
  Returns:    
    Product object
  Example:
    my $product = Product->insert(%args);

=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');

    # This is not a column of Product
    my $hostname = delete $argv->{hostname};

    my $prod;
    if ( $argv->{sysobjectid} ){
	# Check if Manufacturer Entity exists or can be added
	my $ent;
	my $oid = $argv->{sysobjectid};
	$oid =~ s/(1\.3\.6\.1\.4\.1\.\d+).*/$1/o;
	if ( $ent = Entity->search(oid=>$oid)->first ){
	    $logger->debug(sprintf("Product::insert: Manufacturer OID matches %s", 
				   $ent->name));
	}elsif ( $argv->{manufacturer} ){
	    $ent = ref($argv->{manufacturer})? $argv->{manufacturer} : 
		Entity->retrieve($argv->{manufacturer});
	    if ( $ent->oid ){
		if ( $ent->oid ne $oid ) {
		    # There is an entity with the same name and different oid
		    # Use the OID as part of the name to make a unique new one
		    my $entname = "$argv->{manufacturer} ($oid)";
		    $ent = Entity->insert({name=>$entname, oid=>$oid});
		}
	    }else{
		# Entity found but OID not set. Set it now
		$ent->update({oid=>$oid});
	    }
	}else{
	    $class->throw_fatal("Cannot proceed without a manufacturer");
	}
	# Make sure we have the correct role assigned
	my $etype = EntityType->find_or_create({name=>"Manufacturer"});
	my $erole = EntityRole->find_or_create({entity=>$ent, type=>$etype});
	$argv->{manufacturer} = $ent;
    }
    # Now on with the product itself
    if ( !$argv->{type} && $hostname ){
	# Try to guess product type based on hostname
	my $typename;
	my %name2type = %{ $class->config->get('DEV_NAME2TYPE') };
	foreach my $str ( keys %name2type ){
	    if ( $hostname =~ /$str/ ){
		$typename = $name2type{$str};
		last;
	    }
	} 
	if ( $typename ){
	    $argv->{type} = ProductType->search(name=>$typename)->first;
	}
    }	
    $argv->{type} ||= ProductType->search(name=>'Unknown')->first;
    
    ###############################################
    # Insert New product
    $argv->{name} ||= $argv->{part_number} || $argv->{sysobjectid};
    my $newproduct = $class->SUPER::insert($argv);
    
    $logger->info(sprintf("Inserted new product: %s", $newproduct->name));
    return $newproduct;
}
    
############################################################################
# Get lists of products, counting the number of devices
__PACKAGE__->set_sql(by_type => qq{
        SELECT p.name, p.id, COUNT(d.id) AS numdevs
        FROM   device d, product p, producttype t, asset a
        WHERE  a.product_id = p.id 
           AND d.asset_id = a.id
           AND p.type = t.id 
           AND t.id = ?
        GROUP BY p.name, p.id
        ORDER BY numdevs DESC
    });

############################################################################
# Get lists of products, counting the number of devices that are monitored
__PACKAGE__->set_sql(monitored_by_type => qq{
        SELECT p.name, p.id, COUNT(d.id) AS numdevs
        FROM   device d, product p, producttype t, asset a
	WHERE  a.product_id = p.id
           AND d.asset_id = a.id 
           AND p.type = t.id 
           AND d.monitored='1'
           AND t.id = ?
        GROUP BY p.name, p.id
        ORDER BY numdevs DESC
    });


############################################################################
# Get product given Device id
__PACKAGE__->set_sql(by_device => qq{
   SELECT  p.id, p.name, p.type, p.description, p.manufacturer, p.latest_os
     FROM  device d, asset a, product p
    WHERE  d.asset_id = a.id
      AND  a.product_id = p.id
      AND  d.id = ?
   });

=head1 INSTANCE METHODS

=cut

############################################################################
=head2 get_label - Overrides label method
   
  Arguments:
    None
  Returns:
    Slightly prettier label
  Examples:
   print $product->get_label(), "\n";

=cut

sub get_label {
    my $self = shift;
    $self->isa_object_method('get_label');
    my @fields = ($self->manufacturer->get_label, $self->name);
    return join(" ", @fields);
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

