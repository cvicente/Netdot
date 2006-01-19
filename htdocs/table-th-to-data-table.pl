#!/usr/bin/perl -w

# Nathan Collins Wed May  4 22:38:22 PDT 2005

# This makes the headers array for data-table calls.

# "Enhanced" version of table-array.pl.  Adds support for
# accumulation.  Not sure how worthwhile this actually is generally,
# but saves a bit of time when it is needed.  Also, the code it
# generates is little prettier than v1 did.

# Probably braindead script to help convert tables into the list we
# pass to attribute_table.mhtml.  Generated code will still require
# some massaging but should be pretty close to what you're looking
# for.  


die "usage: $0 n m <file>\nto convert lines n..m of <file>\n" if ! (scalar(@ARGV) == 3);

my $html = `sed -ne '$ARGV[0],$ARGV[1]p' $ARGV[2]`;
my $toggle = 1;

print( "<%perl>\n",
       '(@headers, @rows) = ();',
       "\n\n",
       '@headers = (',
       "\n"
       );


# Assume everything is in a table data element and that there is no
# nesting.  Might need to consider table headers and the like.
while ($html =~ m{<t(?:h|d)[^>]*>((.|\n)*?)</t(?:h|d)>|(\%.*)}g) {	# s for . matches \n


my $match = 1;    
    if (! defined ($1)) {
	$match = 3;
    }

if ($match == 1) {
#    print( 'push( @headers, ' );
}

$_ = $$match;
    if (/^%/) { 
	s/^%//;	# Un Mason escape embedded perl lines.
	s/^(\s*)printf/$1${a}sprintf/;	# Accumulate prints.
    }
    else
    {
	s/^(\s*)(.*)\s*$/'$2'/;	# Trim whitespace, quote, and accumulate.
	s/<% (.*?) %>/' . $1 . '/g;	# Un Mason escape variables/method calls.
    }
    s/(\$ui->.*?\(.*)\)/$1, returnAsVar=>1\)/;	# The returnAsVar argument needs to get added to all calls to $ui's methods.

    print "$_, ";
if ($match == 1) {
#    print( ' );' );
}
#print "\n";
}

       
print( ");\n",
       "</%perl>\n",
        "\n",
       '<& attribute_table.mhtml, field_headers=>\@field_headers, data=>\@cell_data &>',
       "\n"
        );
	
