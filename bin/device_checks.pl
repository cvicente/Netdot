#!<<Make:PERL>>

use lib "<<Make:LIB>>";
use Netdot::Model;
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;


my ($HELP, $ENTITY, $NEIG, $DUPLEX, $SITE, $NEW, $DEBUG, $EMAIL);
my $FROM    = Netdot->config->get('ADMINEMAIL');
my $TO      = Netdot->config->get('NOCEMAIL');
my $DAYS    = 1;
my $SUBJECT = 'Netdot Device Checks';

my $usage = <<EOF;
 usage: $0  -e|--entity | -d|--dependencies | -s|--site | -d|--duplex 
            -n|--new | -D|--days
           [-m|--send_mail] [-f|--from] | [-t|--to] | [-S|--subject]

    
    -e, --entity                   report devices with no entity
    -n, --neighbors                report devices with no neighbors
    -s, --site                     report devices with no site
    -d, --duplex                   report duplex mismatches
    -n, --new                      report devices discovered within D days
    -D, --days                     (default: $DAYS)
    -h, --help                     print help (this message)
    -m, --send_mail                send output via e-mail
    -f, --from                     e-mail From line (default: $FROM)
    -S, --subject                  e-mail Subject line (default: $SUBJECT)
    -t, --to                       e-mail To line (default: $TO)
    
EOF
    
# handle cmdline args
my $result = GetOptions( "e|entity"       => \$ENTITY,
			 "n|neighbors"    => \$NEIG,
			 "s|site"         => \$SITE,
			 "d|duplex"       => \$DUPLEX,
			 "n|new"          => \$NEW,
			 "D|days:s"       => \$DAYS,
			 "m|send_mail"    => \$EMAIL,
			 "f|from:s"       => \$FROM,
			 "t|to:s"         => \$TO,
			 "S|subject:s"    => \$SUBJECT,
			 "h|help"         => \$HELP,
			 );

if( ! $result ) {
    print $usage;
    die "Error: Problem with cmdline args\n";
}
if( $HELP ) {
    print $usage;
    exit;
}
unless ( $ENTITY || $NEIG || $SITE || $DUPLEX || $NEW ){
    print $usage;
    die "Error: Must specify either -e, -n, -s, -d or -n\n";
}

# This will be reflected in the history tables
$ENV{REMOTE_USER} = "netdot";
my (@nameless, @lost, @orphans, @homeless, @new, $output);

if ( $ENTITY || $NEIG || $SITE || $NEW ){
    my $it = Device->retrieve_all;
    while ( my $dev = $it->next ){
	unless ( $dev->name && $dev->name->name ){
	    push @nameless, $dev;
	    next;
	}
	if ( $ENTITY ){
	    push @lost, $dev unless ( $dev->used_by  && $dev->used_by->id );
	}
	if ( $SITE ){
	    push @homeless, $dev unless ( $dev->site && $dev->site->id );
	}
	if ( $NEIG ){
	    my $found = 0;
	    foreach my $int ( $dev->interfaces ){
		if ( int($int->neighbor) ) { $found = 1; last }
	    }
	    push @orphans, $dev unless $found;
	}
	if ( $NEW && $DAYS ){
	    my $idate = $dev->date_installed;
	    if ( $idate ne '0000-00-00 00:00:00' ){
		my $now = time;
		my $days_ago_sql = Netdot::Model->sqldate_days_ago($DAYS);
		my $t1 = Netdot::Model->sqldate2time($days_ago_sql);
		my $t2 = Netdot::Model->sqldate2time($idate);
		push @new, $dev if ( $t2 >= $t1 );
	    }
	}
    }
    
    if ( @new ){
	$output .= sprintf("\nThe following devices have been discovered within the last $DAYS days:\n");
	map { $output.= sprintf(" %s\n", $_->fqdn) } @new;
    }
    if ( @nameless ){
	$output .= sprintf("\nThe following devices have no name defined:\n");
	map { $output.= sprintf(" ID: %s\n", $_->id) } @nameless;
    }
    if ( @lost ){
	@lost = sort { $a->name->name cmp $b->name->name } @lost;
	$output .= sprintf("\nThe following devices have no Entity defined:\n");
	map { $output .= sprintf("  %s\n", $_->fqdn) } @lost;
    }
    if ( @homeless ){
	@homeless = sort { $a->name->name cmp $b->name->name } @homeless;
	$output .= sprintf("\nThe following devices have no Site defined:\n");
	map { $output .= sprintf("  %s\n", $_->fqdn) } @homeless;
    }
    if ( @orphans ){
	@orphans = sort { $a->name->name cmp $b->name->name } @orphans;
	$output .= sprintf("\nThe following devices have no neighbors:\n");
	map { $output .= sprintf(" %s\n", $_->fqdn) } @orphans;
    }
}
if ( $DUPLEX ){
    my $list = Interface->find_duplex_mismatches();
    if ( scalar @$list ){
	$output .= sprintf("\nThe following Interfaces have duplex/speed mismatch:\n");
	my $count = 0;
	foreach my $pair ( @$list ){
	    $count++;
	    my $a = Interface->retrieve($pair->[0]);
	    my $b = Interface->retrieve($pair->[1]);
	    my $line = sprintf(" %2d) %s, %s, %s, %s\n     %s, %s, %s, %s", $count,
				$a->get_label, $a->admin_duplex, $a->oper_duplex, $a->speed_pretty,
				$b->get_label, $b->admin_duplex, $b->oper_duplex, $b->speed_pretty
		);
	    $output .= "$line\n\n";
	}
    }
}

if ( $EMAIL && $output ){
    Netdot->send_mail(from    => $FROM,
		      to      => $TO,
		      subject => $SUBJECT, 
		      body    => $output);
}else{
    print STDOUT $output, "\n" if $output;
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
