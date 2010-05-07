package Netdot::REST;

use base qw( Netdot );
use Netdot::Model;
use Data::Dumper;
use strict;

my $logger = Netdot->log->get_logger("Netdot::REST");


=head1 METHODS


=head2 view_obj

	Retrieves a hashref containing object information:
	$table			The name of the object (i.e Product)
	$id			The id of the object
	$follow_links_from	0 or 1 depending on if you want links from data
=cut


sub view_obj{
        my ($class, $table, $id, $follow_links) = @_;
        $class->isa_class_method('view_obj');

	$table = $table."";     #weak typing works great!
        $id = $id."";           #except when it doesn't
	my $obj = $table->retrieve($id);
        if(! $obj){
                return;
        }
        my %rtnHash = ();
	$rtnHash{"id"} = $id;
        my %order = $table->meta_data->get_column_order;
        my %linksto = $table->meta_data->get_links_to;
        my %linksfrom = $table->meta_data->get_links_from;

        my %lf = ();
        if($follow_links){
                foreach my $lf (keys(%linksfrom)){
                        my @t = ();

                        $rtnHash{"links_from"}{$lf} = $class->_get_linked_from($linksfrom{$lf}, $id);
                }
        }
        foreach my $title (keys(%order)){
                if(grep {$_ eq $title} keys(%linksto) && $follow_links){
                        #this piece of data is a forign key
                        $rtnHash{$title} = $class->view_obj($linksto{$title}, $obj->$title);
                }
                else{
                        $rtnHash{$title} = $obj->$title;
                }
        }
        return \%rtnHash;
}

#####################################################################
# Private methods
#####################################################################
=head2
	_get_linked_from 
	$href 	Hash ref containing {ObjectType => column}
	$id	id of the calling object that ObjectType links to

=cut
sub _get_linked_from{
        my ($class, $href, $id) = @_;
	$class->isa_class_method('get_linked_from');
        my @results = ();
        my %h = %$href;
        foreach my $k (keys(%h)){
                my $tabl = $k; #should be the name of a table
                my $col = $h{$k}; #should be the column of the table that links to our thing

                $tabl .= "";
                $col .= "";
                my $search_results = $tabl->search($col => $id);
		while(my $r = $search_results->next){
                        push(@results, $class->view_obj($tabl, $r, 0));
                }

        }
        return \@results;
}


=head1 AUTHORS

Clayton Parker Coleman

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
1;
