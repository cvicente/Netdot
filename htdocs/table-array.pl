#!/usr/bin/perl -w

# Nathan Collins Wed May  4 17:03:04 PDT 2005

# Probably braindead script to help convert tables into the list we
# pass to attribute_table.mhtml.  You will still need to clean up and
# processed for loops.

die "usage: $0 n m <file>\nto convert lines n..m of <file>\n" if ! (scalar(@ARGV) == 3);

my $html = `sed -ne '$ARGV[0],$ARGV[1]p' $ARGV[2]`;
my $toggle = 1;

# Assume everything is in a table data element and that there is no
# nesting.  Might need to consider table headers and the like.
while ($html =~ m|<td[^>]*>(.*?)</td>|sg) {	
    #print $1,"\n";
    if ($toggle) {
	print qq(push( \@field_headers, "$1" );\n);	# Assuming field headers are always simple.
    }else{
	my @lines = split(/\n/,$1);
	foreach (@lines) { 
	    if (/^%/) { s/^%//;}	# Un Mason escape embedded perl lines.
	    else {
		s/^\s*(.*)\s*$/'$1'/;	# Trim whitespace and quote.
		s/<% (.*?) %>/'.$1.'/g;	# Un Mason escape variables/method calls.
	    }
	    s/(\$ui->.*?\(.*)\)/$1, returnAsVar=>1)/;	# This argument gets added to all calls to $ui's methods.
	}
	my $code = join( "\n", grep {$_ !~ /''/} @lines );	# Grab the non empty lines.
        if ($code =~ / if / ) {	# If there is branching there are probably multiple possible outputs.
	    $code = "&{sub{\n".$code."\n}}";
	}else{
	    $code =~ s/\;$//;
	}

	print( "push( \@cell_data, ", 
	       $code,
	       " );\n" );
    }
    ($toggle += 1) %= 2;	# Switch between field_headers and cell_data
}
