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

    my $product = Product->find_or_create(%args);

    ...

=head1 CLASS METHODS

=cut

############################################################################
=head2 find_or_create - Find or Create product

    Checks if Product exists in DB or creates a new one, based on given info

  Arguments:  
    Hash ref with following keys:
     name          - 
     description   - 
     sysobjectid   - (required)
     type          - Can be a ProductType object, id or name
     manufacturer  
     hostname      - (optional) for guessing product type based on device name
  Returns:    
    Product object or undef if error
  Example:
    my $product = Product->find_or_create(%args);

=cut

sub find_or_create {
    my ($class, %argv) = @_;
    $class->isa_class_method('find_or_create');

    my ($name, $description, $sysobjectid, $type, $manufacturer, $hostname) 
	= @argv{"name", "description", "sysobjectid", "type", "manufacturer", "hostname"};
    
    $class->throw_fatal("Model::Product::find_or_create: Missing required arguments")
	unless defined( $sysobjectid || $name );
    
    my $prod;
    if ( $sysobjectid && ($prod = $class->search(sysobjectid=>$sysobjectid)->first) ) {
	$logger->debug(sub{ sprintf("Product known as %s", $prod->name) });
	return $prod;
    }elsif ( $prod = $class->search(name=>$name)->first ) {
	$logger->debug(sub{ sprintf("Product %s found", $prod->name) });
	return $prod;
    }else{
	###############################################
	# Create a new product
	#
	$logger->debug("Product::find_or_create: Adding new Product");
	
	###############################################
	# Check if Manufacturer Entity exists or can be added
	#
	my ($ent, $oid);
	if( $sysobjectid ) {
	    $oid = $sysobjectid;
	    $oid =~ s/(1\.3\.6\.1\.4\.1\.\d+).*/$1/;
	    if ( $ent = Entity->search(oid=>$oid)->first ){
		$logger->info(sprintf("Product::find_or_create: Manufacturer OID matches %s", 
				      $ent->name));
	    }
	}elsif ( $manufacturer ){
	    $ent = Entity->search(name=>$manufacturer)->first; 
	}
	if ( !$ent ){
	    my $entname = $manufacturer || $oid;
	    $ent = Entity->insert({name=>$entname, oid=>$oid});
	    $logger->info("Inserted new Entity: $entname.");
	    my $etype = EntityType->search(name=>"Manufacturer")->first || 0;
	    my $erole = EntityRole->insert({entity=>$ent, type=>$etype});
	}
	
	my $ptype;
	if ( $type ){
	    if ( ref($type) =~ /ProductType/ ){
		# We were given an object
		$ptype = $type;
	    }elsif ( $type =~ /^\d+$/ ){
		# Looks like a ProductType id
		$ptype = ProductType->search(id=>$type)->first;
	    }else{
		# Then it must be a product name
		$ptype = ProductType->search(name=>$type)->first;
	    }
	}
	
	# Try to guess product type based on hostname
	if ( $hostname && !$type ){
	    my $typename;
	    my %name2type = %{ $class->config->get('DEV_NAME2TYPE') };
	    foreach my $str ( keys %name2type ){
		if ( $hostname =~ /$str/ ){
		    $typename = $name2type{$str};
		    last;
		}
	    } 
	    if ( $typename ){
		$ptype = ProductType->search(name=>$typename)->first;
	    }
	}	

	###############################################
	# Insert New product
	#	
	$name ||= $sysobjectid;
	my $newproduct = Product->insert({ name         => $name,
					   description  => $description,
					   sysobjectid  => $sysobjectid,
					   type         => $ptype,
					   manufacturer => $ent,
				       });
	
	$logger->info(sprintf("Inserted new product: %s", $newproduct->name));
	return $newproduct;
    }
}

############################################################################
# Get lists of products
__PACKAGE__->set_sql(by_type => qq{
    SELECT p.name, p.id, COUNT(d.id) AS numdevs
        FROM device d, product p, producttype t
        WHERE d.product = p.id AND
        p.type = t.id AND
        t.id = ?
        GROUP BY p.name, p.id
        ORDER BY numdevs DESC
    });


=head1 INSTANCE METHODS

=cut

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 University of Oregon, all rights reserved.

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

