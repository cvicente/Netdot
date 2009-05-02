#!<<Make:PERL>>
#
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::Exporter;
use Getopt::Long qw(:config no_ignore_case bundling);
use Log::Log4perl::Level;

my $USAGE = <<EOF;
 usage: $0 -t "<Type1, Type2...>" 
         [ -z|--zones <zone1,zone2...> ] [ -n|--nopriv ]
         [ -d|--debug ] [ -h|--help ]
         [ -s|--scope <scope1, scope2>]

    Available types:  Nagios, Sysmon, Rancid, BIND, DHCPD

    BIND exporter Options:
       zones  - Comma-separated list of zone names, or the word 'all'
       nopriv - Exclude private data from zone file (TXT and HINFO)

    DHCPD exporter options:
       scopes - Comma-separated list of global scope names.  If not
                specified, all global scopes will be exported.

EOF
    
my %self;

# handle cmdline args
my $result = GetOptions( 
    "t|types=s"       => \$self{types},
    "z|zones=s"       => \$self{zones},
    "s|scopes=s"      => \$self{scopes},
    "n|nopriv"        => \$self{nopriv},
    "h|help"          => \$self{help},
    "d|debug"         => \$self{debug},
    );

if ( !$result ) {
    print $USAGE;
    die "Error: Problem with cmdline args\n";
}
if ( $self{help} ) {
    print $USAGE;
    exit;
}

defined $self{types} || die "Error: Missing required argument: types (-t)\n";

my $logger = Netdot->log->get_logger('Netdot::Exporter');
my $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);
$logger->add_appender($logscr);

# Notice that $DEBUG is imported from Log::Log4perl
$logger->level($DEBUG) 
    if ( $self{debug} ); 

foreach my $type ( split ',', $self{types} ){
    $type =~ s/\s+//g;
    my $exporter = Netdot::Exporter->new(type=>$type);
    if ( $type eq 'BIND' ){
	unless ( $self{zones} ){
	    print $USAGE;
	    die "Missing required argument 'zones' for BIND export";
	}
	my @zones = split ',', $self{zones};
	if ( scalar(@zones) == 1 && $zones[0] eq 'all' ){
	    $exporter->generate_configs(all=>1, nopriv=>$self{nopriv});
	}else{
	    $exporter->generate_configs(zones=>\@zones, nopriv=>$self{nopriv});
	}
    }elsif ( $type eq 'DHCPD' ){
	if ( $self{scopes} ){
	    my @scopes = split ',', $self{scopes};
	    $exporter->generate_configs(scopes=>\@scopes);
	}else{
	    $exporter->generate_configs();
	}
    }else{
	$exporter->generate_configs();
    }
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
