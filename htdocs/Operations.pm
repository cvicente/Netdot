package Operations;

use Netdot;
use Data::Dumper;

# Helper methods for the operations page

# Given a list of contacts find those that have availability != never
# for one of notify_voice, notify_page, or notify_email.

# Returns array ref of (<contact>, <field>, [<field>, [<field>]])
# array refs where the fields grouped with contact are those suchthat
# contact->field != Never.

sub contactable_contacts {
    my @contacts = @_;
    
    my @fields = qw/notify_voice notify_pager notify_email/;

#     foreach my $c (@contacts) {
# 	_debug(map { $c->$_->name } @fields);
#     }
    
    my @sets = map { 
	$contact = $_; 
	# Anon hash
	{ 'contact' => $contact, 
	  'availabilities' => [grep { length($contact->$_->name) > 0 
					  and $contact->$_->name ne "Never"
				      } @fields
			       ], 
      }
    } @contacts;

    _debug(@sets);

    my @available = grep { scalar @{ $_->{availabilities} } > 0 } @sets;
    
    _debug(@available);

    return @available;
    
# #     return grep { scalar @{ $_ } > 1 } 
# #     map { 
# # 	$contact = $_; 
# # 	[$contact, grep { $contact->$_ ne "Never" } @fields] 
# # 	} @contacts;
}

# Circuits are pretty rare: Use the generic search to find one for
# testing.  The cisco-ts* devices seem to have them.
;{
    package Device;
    sub all_circuits {
	my ($device) = @_;
        return map { ($_->nearcircuits, $_->farcircuits) } $device->interfaces;
    }
}

;{
    package Entity;
    sub all_circuits {
	my ($entity) = @_;
        return map {$_->circuits} $entity->connections;
    }
}

sub _debug {
    #print "<pre>" . Dumper(@_) . "</pre>";
}

# Make a canonical link: one with text the name of the object pointing
# to the view.html page for that object.

# Pass the object reference.
my $ui = Netdot::UI->new;
sub view_link {
    my $obj = shift;
    my %hash = $ui->form_field(object => $obj, column => 'name', 
			       edit => 0, linkPage => 1);
    return $hash{'value'};
}

sub get_object {
    my ($obj, $id, $table) = @_;
    # Assumes no $ids are 0.  I think this is true in MySQL, not sure
    # about other DB's
    $obj || $id && $table->retrieve($id)
	or die "You must supply a valid object id or reference";
}

;{
    package Netdot::DBI;
    # Would like to just have a package variable...
    # Override this in subclasses with special view pages
    sub _viewing_page { "view.html" }
    
    # Want to use view_link on all objects.  For this a meaningful
    # canonical name is needed.  The ``label'' as defined in the
    # metatable (see bin/insert-metadata) seems like a natural choice.
    sub label {
	my $self = shift;
	return $ui->getobjlabel($self, ", ");
    }
    
    sub view_link {
	my $self = shift;
	# Optional second arg gives viewing page.
	my $page = shift || $self->_viewing_page;
	# Doesn't work because the $self->name is a reference
	#return '<a href="' . $self->linkPage . '?table=' . (ref $self) . '&id=' . $self->id . '">' . $self->name . '</a>';


	# Doesn't work because it uses the id for the column passed
	# my %hash = $ui->form_field(object => $self, column => 'name', 
	#		       edit => 0, linkPage => $self->linkPage);
	# return $hash{'value'} || "[ahhhhhh]";

	# Used to use the column ``name'' for the name, but not all
	# objects have that.  So, the label method was added to
	# Netdot::DBI.
	my %pair = $ui->form_field(object => $self, column => 'label');
	my ($table, $id, $name) = ($self->table, 
				   $self->id, 
				   $pair{value});
	return "<a href=\"${page}?table=${table}&id=${id}\"> $name </a>";
    }

    package Device;
    sub _viewing_page { "device.html" }
}

#sub Netdot::DBI::canon_link { return Operations::canon_link(shift); }

# This is braindead
1;
