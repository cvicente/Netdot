#PERL

use lib "PREFIX/lib";
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;
use Netdot::DBI;

my $usage = <<EOF;
 usage: $0  -n|--name | -e|--entity |  -d|--dependencies | -s|--site

    
    -e, --entity                   report devices with no entity
    -d, --dependencies             report devices with no dependencies
    -s, --site                     report devices with no site
    -h, --help                     print help (this message)
    
EOF
    
my $HELP    = 0;
my $ENTITY  = 0;
my $DEPS    = 0;
my $SITE    = 0;
my $DEBUG   = 0;

# handle cmdline args
my $result = GetOptions( "e|entity"       => \$ENTITY,
			 "d|dependencies" => \$DEPS,
			 "s|site"         => \$SITE,
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
unless ( $ENTITY || $DEPS || $SITE ){
    print $usage;
    die "Error: Must specify either -e, -d or -s\n";
}

my (@nameless, @lost, @orphans, @homeless);


my $it = Device->retrieve_all;

while ( my $dev = $it->next ){

    unless ( $dev->name && $dev->name->name ){
	push @nameless, $dev;
	next;
    }
    if ( $ENTITY ){
	push @lost, $dev unless ( $dev->entity  && $dev->entity->id );
    }
    if ( $SITE ){
	push @homeless, $dev unless ( $dev->site && $dev->site->id );
    }
    if ( $DEPS ){
	my $found = 0;
	foreach my $int ( $dev->interfaces ){
	    if ($int->parents || $int->children) { $found = 1; last }
	}
	push @orphans, $dev unless $found;
    }
}



if ( @nameless ){
    print "\nThe following devices have no name defined:\n";
    map { print "  ID: ", $_->id, "\n" } @nameless;
}

if ( @lost ){
    @lost = sort { $a->name->name cmp $b->name->name } @lost;
    print "\nThe following devices have no Entity defined:\n";
    map { print "  ", $_->name->name, "\n" } @lost;
}

if ( @homeless ){
    @homeless = sort { $a->name->name cmp $b->name->name } @homeless;
    print "\nThe following devices have no Site defined:\n";
    map { print "  ", $_->name->name, "\n" } @homeless;
}

if ( @orphans ){
    @orphans = sort { $a->name->name cmp $b->name->name } @orphans;
    print "\nThe following devices have no dependencies defined:\n";
    map { print "  ", $_->name->name, "\n" } @orphans;
}
