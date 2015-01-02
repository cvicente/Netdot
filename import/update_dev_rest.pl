#!/usr/bin/perl -w
#
# Sample code demonstrating the use
# of the REST resource: /rest/updatedev
# for importing device data in a single
# operation.
#


use Netdot::Client::REST;
use Data::Dumper;
use XML::Simple;

my $server = 'http://localhost/netdot';
my $username = 'admin';
my $passwd = 'admin';

my $netdot = Netdot::Client::REST->new(server=>$server,
				       username=>$username,
				       password=>$passwd);

my $xs = XML::Simple->new(
    ForceArray => 1,
    XMLDecl    => 1, 
    KeyAttr    => 'id',
    );

my $info = {
    'sysname' => 'newdevice.localdomain',
    'ipforwarding' => 0,
    'layers' => '01000010',
    'sysobjectid' => '',
    'model'  => 'Foo',
    'os'     => '1.2.3.4',
    'manufacturer' => 'Bar',
    'serial_number' => 'abcd1234',
    
    'interface' => {
	'1' => {
	    'name'   => 'lo0',
	    'number' => '1',
	    'type'   => 'softwareLoopback',
	    'physaddr' => '',
	    'admin_status' => 'up',
	    'oper_status' => 'up',
	    'speed'       => '10000000',
	    'ips' => { 
		'192.168.10.20' => {
		    'address' => '192.168.10.20',
		    'version' => '4',
		    'subnet'  => '192.168.10.20/32'
		},
	    },
	},
	'2' => {
	    'name'   => 'eth0',
	    'number' => '2',
	    'type'   => 'ethernet-csmacd',
	    'physaddr' => 'abcabcabcabc',
	    'admin_status' => 'up',
	    'oper_status' => 'up',
	    'speed'       => '1000000000',
	    'ips' => { 
		'192.168.100.200' => {
		    'address' => '192.168.100.200',
		    'version' => '4',
		    'subnet'  => '192.168.100.0/24'
		},
	    },
	},
    },
};

my $xml = $xs->XMLout($info);

my $r = $netdot->post('updatedev', { name => 'newdevice.localdomain', 
				     info => $xml });
print Dumper($r);

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2014 Carlos Vicente

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
