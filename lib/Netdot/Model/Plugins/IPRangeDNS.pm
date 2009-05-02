package Netdot::Model::Plugins::IPRangeDNS;

use base 'Netdot::Model';
use warnings;
use strict;


############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Plugin object
  Examples:
    
=cut
sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    $self->{logger} = Netdot->log->get_logger('Netdot::Model::Ipblock');
    bless $self, $class;
}

############################################################################
sub generate_records {
    my ($self, %argv) = @_;
    
    if ( $argv{status} eq 'Dynamic' ){
	return $self->generate_dynamic(%argv);
    }elsif ( $argv{status} eq 'Static' ){
	return $self->generate_static(%argv);
    }else{
	$self->throw_user("Cannot generate PTR records for IP status: $argv{status})");
    }
}


############################################################################
sub generate_dynamic {
    my ($self, %argv) = @_;
    return $self->_generate(prefix=>'d', %argv);
}

############################################################################
sub generate_static {
    my ($self, %argv) = @_;
    return $self->_generate(prefix=>'host-', %argv);
}

############################################################################
# _generate - Generates A/AAAA & PTR records
# 
# It figures out the host octets and appends them to the given prefix string
# For example:
#   given the IP - 192.168.10.20
#   it will create PTR records like "d10-20.my-given-domain"
#   
sub _generate {
    my ($self, %argv) = @_;
    my($prefix, $ipstart, $ipend, $fzone, $rzone) 
	= @argv{'prefix', 'start', 'end', 'fzone', 'rzone'};

    $self->throw_fatal("Missing required arguments")
	unless ( $prefix && $ipstart && $ipend && $fzone && $rzone );

    my @rrs;
    my $zname = $rzone->name;
    $zname =~ s/(.*)\.in-addr.arpa/$1/ || 
	$zname =~ s/(.*)\.ip6.arpa/$1/ ||
	$zname =~ s/(.*)\.ip6.int/$1/ ;

    my ($name, $ptrdname);
    for ( my $i=$ipstart->numeric; $i<=$ipend->numeric; $i++ ){
	my $ip = NetAddr::IP->new($i);
	if ( $ip->version eq '4' ){
	    my @octs = split(/\./, $zname);
	    my $p = join '.', reverse @octs;
	    $name = $ip->addr;
	    $name =~ s/$p\.//;
	    $name =~ s/\./-/;
	    $name = $prefix.$name;
	    $ptrdname = "$name.".$fzone->name;

	    my $ipb = Ipblock->search(address=>$ip->addr)->first;

	    # We'll wipe out whatever records were there
	    foreach my $r ( $ipb->ptr_records ){
		$r->delete;
	    }
	    foreach my $r ( $ipb->arecords ){
		$r->delete;
	    }
	    
	    my $ptr = Netdot::Model::RRPTR->insert({ptrdname => $ptrdname, 
						    ipblock  => $ipb, 
						    zone     => $rzone});
	    push @rrs, $ptr;
	    
	    my $rraddr = Netdot::Model::RR->insert({type    => 'A',
						    name    => $name, 
						    ipblock => $ipb, 
						    zone    => $fzone});
	    push @rrs, $rraddr;
	    
	}elsif ( $ip->version eq '6' ){
	    # Pending
	}

    }
    return \@rrs;
}

=head1 AUTHORS

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

# Make sure to return 1
1;
