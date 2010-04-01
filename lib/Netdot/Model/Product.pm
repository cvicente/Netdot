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
    my ($class) = shift;
    $class->isa_class_method('find_or_create');

    my %argv = ref $_[0] eq "HASH" ? %{$_[0]} : @_;

    my ($name, $description, $sysobjectid, $type, $manufacturer, $hostname) 
	= @argv{"name", "description", "sysobjectid", "type", "manufacturer", "hostname"};
 
    $class->throw_fatal("Model::Product::find_or_create: Missing required arguments")
	unless defined( $sysobjectid || $name );
    
    my $prod;
    if ( $sysobjectid && ($prod = $class->search(sysobjectid=>$sysobjectid)->first) ) {
	$logger->debug(sub{ sprintf("Product $sysobjectid known as %s", $prod->name) });
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
	}
	if ( $manufacturer && !$ent ){
	    if($ent = Entity->search(name=>$manufacturer)->first){
                #Ok, there is an entity with the same name, does it have the same oid?
                if(! ($ent = Entity->search(name=>$manufacturer, oid=>$oid)->first)){
                    #eek, it sure dosn't, we'll need to add another entry with the same manufacturer name!
                    my $count = 1;
                    #this technique will take a long time if there are a lot of products with the same name in the db
                    #but that should very rarely happen.
                    while($ent = Entity->search(name=>$manufacturer."[$count]")){
                         if($count < 5){
                             $count+=1;
                         }
                         #enough counting already lets get this overwith!
                         else{
                             $count = int(rand(1000000))
			 }
                    }
                    #we have exited the loop, which means count contains a value that, when combined with the manufacturer's
                    #name, does not exist in the database
                    $manufacturer .= "[$count]";
                    $ent = 0; #set ent to 0 so the next if statement can execute                
                }
	    }
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
	if ( $hostname && !$ptype ){
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
	
	$class->throw_fatal("Product::find_or_create: A product type could not be determined.  Aborting")
	    unless $ptype;

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
# Get lists of products, counting the number of devices
__PACKAGE__->set_sql(by_type => qq{
        SELECT p.name, p.id, COUNT(d.id) AS numdevs
        FROM   device d, product p, producttype t
        WHERE  d.product = p.id 
           AND p.type = t.id 
           AND t.id = ?
        GROUP BY p.name, p.id
        ORDER BY numdevs DESC
    });

############################################################################
# Get lists of products, counting the number of devices that are monitored
__PACKAGE__->set_sql(monitored_by_type => qq{
        SELECT p.name, p.id, COUNT(d.id) AS numdevs
        FROM   device d, product p, producttype t
        WHERE  d.product = p.id 
           AND p.type = t.id 
           AND d.monitored='1'
           AND t.id = ?
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

