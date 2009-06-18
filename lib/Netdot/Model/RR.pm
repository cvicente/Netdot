package Netdot::Model::RR;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 NAME

Netdot::Model::RR - DNS Resource Record Class

=head1 SYNOPSIS

    Objects of this class do not contain actual DNS records.
    Each record type has its own table that references
    this base record.

    RR->search(name=>"some.domain.name")

=head1 CLASS METHODS
=cut

############################################################################
=head2 search - Search Resource Records

    We override the base class to extend functionality:

      - If zone key is not passed, name will be looked up assuming it might
        contain domain info.

  Arguments: 
    Hash with column/value pairs.  
    'name' can be either FQDN or host part of the name
  Returns: 
    RR object or undef
  Examples:
    RR->search(name=>'foo.bar')

=cut
sub search {
    my ($class, @args) = @_;
    $class->isa_class_method('search');

    @args = %{ $args[0] } if ref $args[0] eq "HASH";
    my $opts = @args % 2 ? pop @args : {}; 
    my %argv = @args;

    my ($rr, @sections);
    if ( (exists $argv{name}) && ($argv{name} =~ /\./)  && !exists $argv{zone} ){
	if ( my $zone = (Zone->search(name=>$argv{name}))[0] ){
	    my $name = $zone->name;
	    $argv{name} =~ s/\.$name//;
	    $argv{zone} = $zone->id;
	    return $class->SUPER::search(%argv);
	}else{
	    # Zone not found, just do normal search
	    return $class->SUPER::search(%argv);
	}
    }else{
	return $class->SUPER::search(%argv, $opts);
    }
    return;
}

############################################################################
=head2 search_like - Search Resource Records with wildcards

    We override the base class to extend functionality:

      - If zone key is not passed, name will be looked up assuming it might
        contain domain info.

  Arguments: 
    Hash with column/value pairs.  
    'name' can be either FQDN or host part of the name
  Returns: 
    RR object or undef
  Examples:
    RR->search_like(name=>"foo*.bar")

=cut
sub search_like {
    my ($class, %argv) = @_;
    $class->isa_class_method('search_like');
    $class->throw_fatal('Model::RR::search_like: Missing required arguments')
	unless %argv;

    my ($rr, @sections);
    if ( (exists $argv{name}) && ($argv{name} =~ /\./)  && !exists $argv{zone} ){
	if ( my $zone = (Zone->search(name=>$argv{name}))[0] ){
	    my $name = $zone->name;
	    $argv{name} =~ s/\.$name//;
	    $argv{zone} = $zone->id;
	    return $class->SUPER::search_like(%argv);
	}else{
	    # Zone not found, just do normal search
	    return $class->SUPER::search_like(%argv);
	}
    }else{
	return $class->SUPER::search_like(%argv);
    }
    return;
}


############################################################################
=head2 insert - Insert new RR

    We override the common insert method for extra functionality

 Argsuments: 
    name        Unique record identifier (AKA "owner")
    zone        Zone object, id or name. If not defined, will assume 
                'DEFAULT_DNSDOMAIN' from config file
                If defined, will create if necessary.
    type        <A|AAAA|TXT|HINFO|CNAME|NS|MX|NAPTR|SRV|PTR|LOC> 
                Create records for these types 
                (need to pass their specific arguments)
    rr          Owner RR (if already created)
    update_ptr  If Creating a A/AAAA, automatically insert corresponding PTR
    
  Returns: 
    New RR object, or RRADDR, RRTXT, etc. if type is specified.

  Examples:
    my $newrr = RR->insert( { name=> $name } );

=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    $class->throw_fatal('Model::RR::insert: Missing required parameters: name or rr')
	unless ( defined $argv->{name} || defined $argv->{rr} );

    # Set default zone if needed
    $argv->{zone} = $class->config->get('DEFAULT_DNSDOMAIN') 
	unless ($argv->{zone});
    
    # Insert zone if necessary;
    my $zone;
    if ( (ref( $zone = $argv->{zone} ) =~ /Zone/)
	 || ( $zone = (Zone->search(id   =>$argv->{zone}))[0] )
	 || ( $zone = (Zone->search(name=>$argv->{zone}))[0] )
	){
    }else{
	$logger->debug(sub{ sprintf("Zone not found: \"%s\".  Inserting.", $argv->{zone}) });
	$zone = Zone->insert({ name => $argv->{zone} });
	$logger->info(sprintf("Inserted new Zone: %s", $zone->get_label));
    }

    my $rr;

    if ( $argv->{rr} ){
	$rr = (ref($argv->{rr}))? $argv->{rr} : RR->retrieve($argv->{rr});
    }elsif ( $rr = $class->search(name=>$argv->{name}, zone=>$zone)->first ){
	if ( !defined $argv->{type} ){
	    $class->throw_user(sprintf("RR::Insert: %s.%s already exists!", $rr->name, $rr->zone->name));
	}
    }else{
	# Set some defaults
	my $auto_update = defined($argv->{auto_update})? 
	    $argv->{auto_update} : Netdot->config->get('DEVICE_IP_NAME_AUTO_UPDATE_DEFAULT');
	
	my %state = (name        => $argv->{name},
		     zone        => $zone->id,
		     active      => defined($argv->{active})? $argv->{active} : 1,
		     auto_update => $auto_update,
	    );

	$class->_validate_args(\%state);
	
	$rr = $class->SUPER::insert(\%state);
	
	if ( !defined $argv->{type} ){
	    return $rr;
	}
    }
    
    my %args;
    if ( defined $argv->{ttl} ){
	if ( $argv->{ttl} =~ /^(?:\d+[WDHMS]?)+$/i ){
	    $args{ttl} = $argv->{ttl};
	}else{
	    $logger->warn("Invalid TTL: ".$argv->{ttl});
	}
    }

    if ( $argv->{type} eq 'A' || $argv->{type} eq 'AAAA' ){
	$class->throw_user("Missing required argument: ipblock")
	    unless defined $argv->{ipblock};
	# We handle both an ipblock object and a plain address string
	my $ipb;
	if ( ref($argv->{ipblock}) ){
	    $ipb = $argv->{ipblock};
	}elsif ( !($ipb = Netdot::Model::Ipblock->search(address=>$argv->{ipblock})->first) ){
	    $ipb = Netdot::Model::Ipblock->insert({ address => $argv->{ipblock},
						    status  => 'Static' });
	}
	%args = (rr=>$rr, ipblock=>$ipb);
	$args{update_ptr} = 1 if $argv->{update_ptr};
	return RRADDR->insert(\%args);

    }elsif ( $argv->{type} eq 'TXT' ){
	$class->throw_user("Missing required argument: txtdata")
	    unless defined $argv->{txtdata};
	my %args = (rr=>$rr, txtdata=>$argv->{txtdata});
	$args{ttl} = $argv->{ttl} if defined $argv->{ttl};
	return RRTXT->insert(\%args);
    
    }elsif ( $argv->{type} eq 'HINFO' ){
	$class->throw_user("Missing required arguments: cpu and/or os")
	    unless ( defined $argv->{cpu} && defined $argv->{os} );
	my %args = (rr=>$rr, cpu=>$argv->{cpu}, os=>$argv->{os});
	$args{ttl} = $argv->{ttl} if defined $argv->{ttl};
	return RRHINFO->insert(\%args);
    
    }elsif ( $argv->{type} eq 'MX' ){
	$class->throw_user("Missing required argument: exchange")
	    unless defined $argv->{exchange};
	my %args = (rr=>$rr, exchange=>$argv->{exchange});
	$args{preference} = $argv->{preference} || 0;
	$args{ttl} = $argv->{ttl} if defined $argv->{ttl};
	return RRMX->insert(\%args);
	
    }elsif ( $argv->{type} eq 'CNAME' ){
	$class->throw_user("Missing required argument: cname")
	    unless defined $argv->{cname};
	my %args = (name=>$rr, cname=>$argv->{cname});
	$args{ttl} = $argv->{ttl} if defined $argv->{ttl};
	return RRCNAME->insert(\%args);

    }elsif ( $argv->{type} eq 'NS' ){
	$class->throw_user("Missing required argument: nsdname")
	    unless defined $argv->{nsdname};
	my %args = (rr=>$rr, nsdname=>$argv->{nsdname});
	$args{ttl} = $argv->{ttl} if defined $argv->{ttl};
	return RRNS->insert(\%args);

    }elsif ( $argv->{type} eq 'PTR' ){
	$class->throw_user("Missing required arguments: ptrdname, ipblock")
	    unless ( defined $argv->{ptrdname} && defined $argv->{ipblock} );
	my $ipb;
	if ( ref($argv->{ipblock}) ){
	    $ipb = $argv->{ipblock};
	}elsif ( !($ipb = Netdot::Model::Ipblock->search(address=>$argv->{ipblock})->first) ){
	    $ipb = Netdot::Model::Ipblock->insert({ address => $argv->{ipblock},
						    status  => 'Static' });
	}
	my %args = (rr=>$rr, ipblock=>$ipb, ptrdname=>$argv->{ptrdname});
	$args{ttl} = $argv->{ttl} if defined $argv->{ttl};
	return RRPTR->insert(\%args);

    }elsif ( $argv->{type} eq 'LOC' ){
	my %args = (rr=>$rr); 
	foreach my $field ( qw/size horiz_pre vert_pre latitude longitude altitude/ ){
	    $class->throw_user("Missing required argument: $field")
		unless (defined $argv->{$field});
	    $args{$field} = $argv->{$field};
	}
	$args{ttl} = $argv->{ttl} if defined $argv->{ttl};
	return RRLOC->insert(\%args);    

    }elsif ( $argv->{type} eq 'NAPTR' ){
	my %args = (rr=>$rr); 
	foreach my $field ( qw/order_field preference flags services regexpr replacement/ ){
	    $class->throw_user("Missing required argument: $field")
		unless (defined $argv->{$field});
	    $args{$field} = $argv->{$field};
	}
	$args{ttl} = $argv->{ttl} if defined $argv->{ttl};
	return RRNAPTR->insert(\%args);    

    }elsif ( $argv->{type} eq 'SRV' ){
	my %args = (name=>$rr); 
	foreach my $field ( qw/port priority target weight/ ){
	    $class->throw_user("Missing required argument: $field")
		unless (defined $argv->{$field});
	    $args{$field} = $argv->{$field};
	}
	$args{ttl} = $argv->{ttl} if defined $argv->{ttl};
	return RRSRV->insert(\%args);    

    }else{
	$class->throw_user("Unrecognized type: $argv->{type}");
    }

}

=head1 INSTANCE METHODS
=cut

##################################################################
=head2 update

    Override base method to:
       - Add option to update related RRPTR if name changes
  Arguments:
    Hashref with key/value pairs, plus:
       update_ptr - (flag)
  Returns:
    Number of rows updated or -1
  Examples:
    $rr->update(\%args)

=cut
sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');
    
    my $update_ptr = 1; # On by default
    if ( defined $argv->{update_ptr} && $argv->{update_ptr} == 0 ){
	$update_ptr = 0;
	delete $argv->{update_ptr};
    }

    $self->_validate_args($argv);

    my @res = $self->SUPER::update($argv);

    if ( $update_ptr ){
	if ( my @arecords = $self->arecords ){
	    foreach my $rraddr ( @arecords ){
		my $ip = $rraddr->ipblock;
		if ( my $ptr = ($ip->ptr_records)[0] ){
		    $ptr->update({ptrdname=>$self->get_label})
			if ( $ptr->ptrdname ne $self->get_label );
		}
	    }
	}
    }
    
    return @res;
}

##################################################################
=head2 get_label - Override get_label method

    Returns the full Resource Record name

  Arguments:
    None
  Returns:
    string
  Examples:
    print $rr->get_label();

=cut
sub get_label {
    my $self = shift;
    $self->isa_object_method('get_label');
    my $name = ($self->name eq '@')? "" : $self->name;
    if ( $self->zone ){
	if ( $name ){
	    return sprintf("%s.%s", $name, $self->zone->name);
	}else{
	    return $self->zone->name;
	}
    }else{
	return $name;
    }
}

##################################################################
=head2 as_text

    Returns text representation of this RR (owner) and all its 
    related records

  Arguments:
    None
  Returns:
    string
  Examples:
    print $rr->as_text();

=cut
sub as_text {
    my $self = shift;
    $self->isa_object_method('as_text');
    my $text = "";
    my @records;

    foreach my $m ( qw/arecords txt_records hinfo_records cnames ns_records 
                     mx_records ptr_records naptr_records srv_records/ ){
	push @records, $self->$m;
    }
    
    foreach my $record ( @records ){
	$text .= $record->as_text;
	$text .= "\n";
    }

    return $text;
}

##################################################################
=head2 add_host

    Adds a host

  Arguments:
    Hash with following keys:
    address
    hostname
    zone
    block
    ethernet
    person
    contact_name
    contact_email
    contact_phone
  Returns:
    RR id
  Examples:
    print RR->add_host();

=cut

sub add_host {
    my ($class, %argv) = @_;
    
    if (!($argv{address} && $argv{hostname} && $argv{zone} && $argv{block})) {
	$class->throw_fatal("Missing required arguments.");
    }
    
    # We want this to be atomic
    my $rr;
    Netdot::Model->do_transaction(
	sub{
	    my $rraddr = RR->insert({type       => 'A', # The RR class would do the right thing if it's v6
				     ipblock    => $argv{address}, 
				     name       => $argv{hostname}, 
				     zone       => $argv{zone},
				     update_ptr => 1,
				    });
	    
	    $rr = $rraddr->rr;
	    
	    # HINFO
	    if ( $argv{cpu} && $argv{os} ){
		my %hinfo = (rr  => $rr, 
			     type=> 'HINFO',
			     cpu => $argv{cpu},
			     os  => $argv{os});
		RR->insert(\%hinfo);
	    }
	    
	    # LOCATION
	    if ( $argv{site_id} || $argv{site_name} ){
		my $sname = ($argv{site_id})? Site->retrieve($argv{site_id})->get_label : $argv{site_name};
		my $txtdata =  "LOC: $sname";
		if ( $argv{room_id} || $argv{room_number} ){
		    my $room = ($argv{room_id})? Room->retrieve($argv{room_id})->get_label : $argv{room_number};
		    $txtdata .= " ".$room;
		}
		RR->insert({rr      => $rr, 
			    type    =>'TXT',
			    txtdata => $txtdata,
			   });
	    }
	    
	    # CONTACTS
	    if ( $argv{person} ){
		# Add the current user as a contact
		my $txtdata = "CON: ".$argv{person}->get_label;
		$txtdata .= " (".$argv{person}->email.")" if $argv{person}->email; 
		$txtdata .= ", ".$argv{person}->office if $argv{person}->office;
		RR->insert({rr      => $rr, 
			    type    =>'TXT',
			    txtdata => $txtdata,
			   });
	    }
	    
	    # Add additional contact info
	    if ( $argv{contact_name} ){
		my $txtdata = "";
		$txtdata =  "CON: ".$argv{contact_name};
		$txtdata .= " (".$argv{contact_email}.")" if $argv{contact_email}; 
		$txtdata .= ", ".$argv{contact_phone} if $argv{contact_phone}; 
		if ( $argv{room_id} || $argv{room_number} ){
		    my $room = ($argv{room_id})? Room->retrieve($argv{room_id})->get_label : $argv{room_number};
		    $txtdata .= " ".$room;
		}
		RR->insert({rr      => $rr, 
			    type    =>'TXT',
			    txtdata => $txtdata,
			   });
	    }
	    
	    # DHCP
	    if ( $argv{ethernet} ){
		my $physaddr = PhysAddr->find_or_create({address=>$argv{ethernet}});
		
		# Create host scope
		my $container;
		unless ( $container = ($argv{block}->dhcp_scopes)[0] ){
		    $class->throw_user("Subnet ".$argv{block}->get_label." not dhcp-enabled (no Subnet scope found).");
		}
		my $host;
		if ( $host = DhcpScope->search(name=>$argv{address})->first ){
		    $class->throw_user("A DHCP scope for host $argv{address} already exists!");
		}else{
		    $host = DhcpScope->insert({name      => $argv{address},
					       type      => 'host',
					       ipblock   => $rraddr->ipblock,
					       physaddr  => $physaddr,
					       container => $container});
		}
	    }
	    
	});
    return $rr;
}

############################################################################
=head2 validate_name - Name validation for unprivileged users
    
    This method is called from specific UI components that take
    RR name input from unpriviledged users.  The regular expression
    is a configuration item.
    
  Args: 
    RR name string
  Returns: 
    True, or throws exception if validation fails
  Examples:
    RR->validate_name($name);

=cut
sub validate_name {
    my ($self, $name) = @_;
    
    if ( my $regex = Netdot->config->get('DNS_NAME_USER_INPUT_REGEX') ){
	if ( $name =~ /$regex/ ){
	    $self->throw_user("Invalid name: $name. Name contains invalid characters");
	}
    }
    1;
}


############################################################################
# PRIVATE METHODS
############################################################################

############################################################################
# _validate_args - Validate arguments to insert and update
#
#  Args: 
#    hashref
#  Returns: 
#    True, or throws exception if validation fails
#  Examples:
#    $class->_validate_args($argv);
#
sub _validate_args {
    my ($self, $argv) = @_;
    
    my $zone;
    if (ref($self)){
	$zone = $self->zone;
    }
    if ( defined $argv->{zone} ){
	if ( !ref($argv->{zone}) ){
	    if ( $argv->{zone} =~ /\D+/ ){
		$zone = Zone->search(name=>$zone)->first;
	    }else{
		Zone->retrieve($argv->{zone});
	    }
	}
    }
    if ( defined $argv->{name} ){
	my $name = $argv->{name};

	# Length restrictions
	unless ( length($name) >= 1 && length($name ) < 64){
	    $self->throw_user("Invalid name: $name. Length must be between 1 and 63 characters");
	}
	if ( $zone ){
	    my $fqdn = $name.".".$zone->name;
	    if ( length($fqdn) > 255 ){
		$self->throw_user("Invalid FQDN: $fqdn. Length exceeds 255 characters");
	    }
	}
    }
    1;
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

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

