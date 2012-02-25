package Netdot::REST;

=head1 NAME

Netdot::REST - Server-side RESTful interface

=head1 DESCRIPTION

Netdot::REST groups common methods related to Netdot's RESTful interface.
The RESTful interface provides access to the Netdot database over the HTTP/HTTPS protocol.

=head1 SYNOPSIS

    use Netdot::REST
    my $rest = Netdot::REST->new();
    $rest->handle_resource(resource=>$resource, r=>$r, %ARGS);

=cut
use base qw( Netdot );
use Netdot::Model;
use XML::Simple;
use Data::Dumper;
use Apache2::Const -compile => qw(FORBIDDEN HTTP_UNAUTHORIZED OK NOT_FOUND 
                                  HTTP_BAD_REQUEST HTTP_NOT_ACCEPTABLE);
use strict;

my $logger = Netdot->log->get_logger("Netdot::REST");

=head1 METHODS

############################################################################
=head2 new - Constructor

  Arguments:
    user     (R) Netdot user object
    manager  (R) Permission manager object
  Returns:
    Netdot::REST object
  Examples:
    $rest = Netot::REST->new(user=>$user, manager=>$manager);

=cut
sub new { 
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};

    foreach my $arg ( qw/user manager/ ){
	$self->{$arg} = $argv{$arg} ||
	    Netdot->throw_fatal("Missing required argument: $arg");
    }

    bless $self, $class;
    wantarray ? ( $self, '' ) : $self; 
}
 

############################################################################
=head2 handle_resource - Calls appropriate REST operation based on request
    
    A resource is the part of the URI between the Netdot URL and any arguments.
    For example, in this URI:

        http://host.localdomain/netdot/device/1

    the resource is "device/1", which for a GET request, will return the contents of Device id 1.

    Also, using this URI with a GET request:

            http://host.localdomain/netdot/device

    this interface will return the contents of all device objects in the DB.

    Moreover, you can specify certain search filters to limit the scope of a GET request:

            http://host.localdomain/netdot/device?sysname=host1

    This will perform a search and return all devices whose sysname field is 'host1'.

    The special keyword 'meta_data' used instead of an object ID will provide information
    about the object's class:

            http://host.localdomain/netdot/device/meta_data

    An existing resource can be updated by using the 'POST' method with relevant parameters.  
    For example, a POST request to the following URI and POST data:

            http://host.localdomain/netdot/device/1    {sysname=>'newhostname'}

    will update the 'sysname' field of the Device object with id 1.  

    Similarly, a new object can be created with a POST request.  However, in this case 
    the object id must be left out:

            http://host.localdomain/netdot/person      {firstname=>'John', lastname=>'Doe'}

    Lastly, objects can be deleted by using the 'DELETE' HTTP method.

  Arguments:
    Hash with following keys:
       resource    - resource string from URI
       r           - Apache request object
       rest of HTTP args
  Returns:
    Sends content (e.g. XML-formatted) to STDOUT.
  Examples:
    $nr->handle_resource(resource=>'Device/1', r=>$r);
    $nr->handle_resource(resource=>'Device', r=>$r, sysname=>host1, site=>2);

=cut
sub handle_resource {
    my ($self, %argv) = @_;
    
    my $resource = delete $argv{resource} || $self->throw_fatal("You need to pass resource");
    my $r = delete $argv{r}               || $self->throw_fatal("You need to pass request object");
    $self->{request} = $argv{r};

    # Get relevant HTTP headers from request object
    my $headers = $self->{request}->headers_in;
    
    $logger->info(sprintf("Netdot::REST::handle_resource: %s request for %s?%s from %s (%s)", 
			  $self->{request}->method, 
			  $resource, 
			  $self->{request}->args,
			  $self->{request}->connection->remote_ip, 
			  $headers->{'User-Agent'}
		  ));

    # Deal with Accept header
    $self->check_accept_header($headers->{Accept}) if ( $headers->{Accept} );

    # Get our valid netdot objects
    my %objects;
    foreach my $t ( Netdot->meta->get_tables() ){
	$objects{$t->db_name} = $t->name;
    }

    # Split the URI into its component elements
    my @elem = split /\//, $resource;

    if ( $elem[0] && (my $table = $objects{lc($elem[0])}) ){
	# We have a matching object class
	if ( my $id = $elem[1] ){
	    if ( $id =~ /^\d+$/ ){
		# We have an object ID
		if ( $self->{request}->method eq 'GET' ){
		    my %get_args = (table=>$table, id=>$id);
		    if ( $argv{depth} ){
			$get_args{depth} = $argv{depth};
		    }
		    if ( $argv{no_linked_from} ){
			$get_args{no_linked_from} = $argv{no_linked_from};
		    }
		    my $o = $self->get(%get_args);
		    $self->print_formatted($o);

		}elsif ( $self->{request}->method eq 'POST' ){
		    my $o = $self->post(table=>$table, id=>$id, %argv);
		    $self->print_formatted($o);

		}elsif ( $self->{request}->method eq 'DELETE' ){
		    $self->delete(table=>$table, id=>$id);
		}
	    }elsif ( $id eq 'meta_data' ){
		if ( $self->{request}->method eq 'GET' ){
		    # Show metadata for this class
		    my $m = $table->meta_data();
		    my %meta = %$m;
		    delete $meta{meta};
		    $self->print_formatted(\%meta);
		}
	    }else{
		# Invalid ID
		$self->throw(code=>Apache2::Const::HTTP_BAD_REQUEST, 
				  msg=>'Netdot::REST::handle_resource: Bad request: Invalid ID'); 
	    }
	}else{
	    if ( $self->{request}->method eq 'GET' ){
		# A lack of id means we're working in plural
		my $results;
		my $depth;
		my $no_linked_from;
		if ( %argv ){
		    # We were given a query hash
		    # Remove non-fields
		    $depth = delete $argv{depth};
		    $no_linked_from = delete $argv{no_linked_from};
		}
		if ( %argv ){
		    # If there are any args left do a search with them
		    $results = $table->search(%argv);
		}else{
		    $results = $table->retrieve_all();
		}
		if ( $results ){
		    my @objs;
		    while ( my $o = $results->next ){
			my %get_args = (obj=>$o);
			$get_args{depth} = $depth if ( $depth );
			$get_args{no_linked_from} = $no_linked_from if ( $no_linked_from );
			push @objs, $self->get(%get_args);
		    }
		    $self->print_formatted({$table=>\@objs});
		}else{
		    $self->throw(code=>Apache2::Const::NOT_FOUND, msg=>"Not found"); 
		}

	    }elsif ( $self->{request}->method eq 'POST' ){
		# A lack of id means we're inserting a new object
		my $o = $self->post(table=>$table, %argv);
		$self->print_formatted($o);
	    }
	}
    }else{
	$self->throw(code=>Apache2::Const::HTTP_BAD_REQUEST, msg=>'Netdot::REST::handle_resource: Bad request'); 
    }
}

############################################################################
=head2 get - Retrieves a hashref containing object information
    
    In the case of foreign key fields, this method will return two hash keys:

    "column_name"        containing the string label of the foreign object
    "column_name_xlink"  containing a resource name useful to obtain the foreign
                         object using the REST interface.

    For example, while retrieving a Device object, the snmp_target field will
    result in:

    snmp_target       => "192.168.1.1"
    snmp_target_xlink => "Ipblock/1"

    In the case of objects linking to the given record, the returned hashref
    will include a key called "linked_from" containing arrays of resources
    which can be used to obtain those records using the REST interface.
    You can omit these resources by using the 'no_linked_from' parameter

    Arguments:
       Hash containing the following keys:
       obj             Object
       table	       Object class
       xlink           xlink string (see above)
       id	       The id of the object
       depth           How many levels of foreign objects to return (default: 0)    
       no_linked_from  Do not return foreign objects referencing this object
    Returns:
       hashref containing object information
    Examples:
       $rest->get(table=>'device', id=>1);
=cut
sub get{
    my ($self, %argv) = @_;
    $self->isa_object_method('get');

    unless ( $argv{obj} || ($argv{table} && $argv{id}) || $argv{xlink} ){
	$self->throw_fatal("Missing required arguments");
    }

    if ( $argv{xlink} ){
	($argv{table}, $argv{id}) = split(/\//, "$argv{xlink}");
    }

    my $obj = $argv{obj} || $argv{table}->retrieve($argv{id});
    unless ( $obj ) {
	my $msg = sprintf("Netdot::REST::get: %s/%s not found", $argv{table}, $argv{id});
	$self->throw(code=>Apache2::Const::NOT_FOUND, msg=>$msg); 
    }
    unless ( $self->{manager}->can($self->{user}, 'view', $obj) ){
	$self->throw(code=>Apache2::Const::HTTP_FORBIDDEN, 
			  msg=>"Netdot::REST::get: User not allowed to view this object");	    
    }

    $argv{depth} ||= 0;
    $argv{depth} = 0 if ( $argv{depth} < 0 );

    my %ret;
    $ret{id} = $obj->id;

    my %order   = $obj->meta_data->get_column_order;
    my %linksto = $obj->meta_data->get_links_to;

    unless($argv{no_linked_from}){
	$ret{linked_from} = $self->_get_linked_from(obj=>$obj, depth=>$argv{depth});
    }
    
    foreach my $col ( keys(%order) ){
	if ( grep {$_ eq $col} keys(%linksto) ){
	    # this piece of data is a foreign key
	    if ( my $fid = int($obj->$col) ){
		my $fclass = $linksto{$col};
		if ( $argv{depth} ){
		    $ret{$col} = $self->get(
			table          => $fclass, 
			id             => $fid, 
			depth          => $argv{depth}-1,
			no_linked_from => $argv{no_linked_from},
			);
		}else{
		    my $fobj = $obj->$col;
		    $ret{$col} = $fobj->get_label;
		    my $xlink = $fclass."/".int($obj->$col);
		    $ret{$col.'_xlink'} = $xlink;
		}
	    }else{
		$ret{$col} = 0;
	    }
	} else{
	    $ret{$col} = $obj->$col;
	}
    }

    return \%ret;
}


############################################################################
=head2 post - Inserts or updates a Netdot object

  Arguments:
    Hash containing the following keys:
    obj               Object
    table	      Object class
    id	              The id of the object (required if updating)
    rest of key/value pairs
  Returns:
    hashref containing object information
  Examples:
    my $o = $rest->post(table=>'device', id=>1, field1=>value1, field2=>value2);
=cut
sub post{
    my ($self, %argv) = @_;
    $self->isa_object_method('post');
    
    unless ( $argv{obj} || ($argv{table} && $argv{id}) ){
	$self->throw_fatal("Missing required arguments");
    }
    unless ( $argv{data} ){
	$self->throw_fatal("Missing required arguments: data");
    }
    
    my $obj = $argv{obj} || $argv{table}->retrieve($argv{id});
    unless ( $obj ) {
	my $msg = sprintf("Netdot::REST::post: %s/%s not found", $argv{table}, $argv{id});
	$self->throw(code=>Apache2::Const::NOT_FOUND, msg=>$msg); 
    }
    # These are not part of the data. Remove them.
    foreach my $f ( qw/obj table id/ ){
	delete $argv{$f};
    }
    if ( $obj ){
	# We are updating an existing object
	# Only admins can edit things this way
	my $user_type = $self->{user}->getAttribute('USER_TYPE');
	unless ( $user_type && ($user_type eq 'Admin') ){
 	    $self->throw(code=>Apache2::Const::HTTP_FORBIDDEN, 
			      msg=>"Netdot::REST::post: User not allowed to edit objects this way");
	}
	
	eval {
	    $obj->update(\%argv);
	};
	if ( my $e = $@ ){
	    $self->throw(code=>Apache2::Const::HTTP_BAD_REQUEST, 
			 msg=>'Netdot::REST::post: Bad request: $e');
	}
	return $self->get(obj=>$obj);
    }else{
	# We are inserting a new object
	my $obj;
	eval {
	    $obj = $argv{table}->insert(\%argv);
	};
	if ( my $e = $@ ){
	    $self->throw(code=>Apache2::Const::HTTP_BAD_REQUEST, 
			 msg=>'Netdot::REST::post: Bad request: $e');
	}
	return $self->get(obj=>$obj);
    }
}

############################################################################
=head2 delete - Delete a Netdot object

    Arguments:
       Hash containing the following keys:
       obj            Object
       table	      Object class
       id	      The id of the object
    Returns:
       True if successful
    Examples:
       $rest->delete(table=>'device', id=>1);
=cut
sub delete{
    my ($self, %argv) = @_;
    $self->isa_object_method('delete');

    unless ( $argv{obj} || ($argv{table} && $argv{id}) ){
	$self->throw_fatal("Missing required arguments");
    }

    my $obj = $argv{obj} || $argv{table}->retrieve($argv{id});
    unless ( $obj ) {
	$self->throw(code=>Apache2::Const::NOT_FOUND, msg=>"Not found"); 
    }
    # Only admins can delete things this way
    my $user_type = $self->{user}->getAttribute('USER_TYPE');
    unless ( $user_type && ($user_type eq 'Admin') ){
	$self->throw(code=>Apache2::Const::HTTP_FORBIDDEN, 
			  msg=>"Netdot::REST::delete: User not allowed to delete objects this way");
    }
	
    eval {
	$obj->delete();
    };
    if ( my $e = $@ ){
	$self->throw(code=>Apache2::Const::HTTP_BAD_REQUEST, msg=>'Bad request');
    }

}


##################################################################
=head2 request - Get/Set request attribute

  Arguments: 
    Apache request object (optional)
  Returns:
    Apache request object
  Examples:
    $rest->request($r);
=cut
sub request {
    my ($self, $r) = @_;
    $self->{request} = $r if $r;
    return $self->{request};
}

##################################################################
=head2 media_type - Get/Set media_type attribute

  Arguments: 
    string
  Returns:
    media_type attribute
  Examples:
    $rest->media_type('xml');
=cut
sub media_type {
    my ($self, $r) = @_;
    $self->{request} = $r if $r;
    return $self->{request};
}


##################################################################
=head2 print_formatted - Print formatted data to stdout

  Arguments: 
    hashref with data to format
  Returns:
    formatted data
  Examples:
    $rest->print_formatted(\%hash);
=cut
sub print_formatted {
    my ($self, $data) = @_;
    
    $self->throw_fatal("Missing required arguments") 
	unless ( $data );
    
    my $mtype = $self->{media_type} || 'xml';
    
    if ( $mtype eq 'xml' ){
	unless ( $self->{xs} ){
	    # Instantiate the XML::Simple class
	    $self->{xs} = XML::Simple->new(
		ForceArray => 1,
		XMLDecl    => 1, 
		KeyAttr    => 'id',
		);
	}
	my $xml = $self->{xs}->XMLout($data);
	$self->{request}->content_type(q{text/xml; charset=utf-8});

	print $xml;
    }
}

##################################################################
=head2 check_accept_header - Sets and validates media_type and version

  Arguments: 
    Accept header string
  Returns:
    True if OK
  Examples:
    $rest->check_accept_header($headers->{Accept});
=cut
sub check_accept_header{
    my ($self, $accept) = @_;
    $logger->debug(sprintf("Netdot::REST::handle_resource: %s, Accept: %s", 
			   $self->{request}->connection->remote_ip, $accept
		   ));
    
    my @headers = split m/,(\s+)?/, $accept;
    foreach my $header ( @headers ){
	my ($mtype, $parameters) = split m/;(\s+)?/, $header;
	if ( $mtype eq 'text/xml' || $mtype eq 'application/xml' ){
	    $self->{media_type} = 'xml';
	    if ( $parameters =~ /version=(\w+)/ ){
		# This will be used in future versions of this API for backwards compatibility
		$self->{version} = $1;
	    }
	    last;
	}
    }
    # At this point, if we haven't found any supported media types, give up
    unless ( $self->{media_type} ){
	$self->throw(code=>Apache2::Const::HTTP_NOT_ACCEPTABLE, 
			  msg=>'Netdot::REST::handle_resource: no acceptable media type found'); 
    }
    1;
}

##################################################################
=head2 throw - Call SUPER::throw_rest

    Prettier than calling $rest->throw_rest :-)

  Arguments: 
    See Netdot.pm
  Returns:
    exception
  Examples:
    $rest->throw(code=>Apache2::Const::HTTP_BAD_REQUEST, msg=>"Bad request: $e"); 
=cut
sub throw {
    my ($self, %args) = @_;
    return $self->SUPER::throw_rest(@_);
}

##################################################################
#
# Private Methods
#
##################################################################

# _get_linked_from - Get list of objects that point to us
#    
#     Arguments:
#        Hash with following keys:
#        object
#        depth
#     Returns:
#        Hash ref where key=method name, value=array of "Class/ID" strings
#     Examples:
#        my $l_from = $rest->_get_linked_from($obj);
#
sub _get_linked_from{
    my ($self, %argv) = @_;
    $self->isa_object_method('_get_linked_from');
    
    my $obj   = $argv{obj}   || $self->throw_fatal("Missing required arg: obj");
    my $depth = $argv{depth};

    my %linksfrom = $obj->meta_data->get_links_from();

    my %results;
    foreach my $i ( keys %linksfrom ){
	my $rtable = (keys %{$linksfrom{$i}})[0]; # Table that points to us
	my @robjs = $obj->$i; # Objects that point to us
	if ( $depth ){
	    map { push @{$results{$i}}, $self->get(table=>$rtable, id=>$_->id, depth=>$depth-1) } @robjs;
	}else{
	    map { push @{$results{$i}}, $rtable.'/'.$_->id } @robjs;
	}
    }
    return \%results if %results;
}


=head1 AUTHORS

Carlos Vicente & Clayton Parker Coleman

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
