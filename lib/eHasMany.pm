package Class::DBI::Relationship::eHasMany;

use strict;
use warnings;

use base 'Class::DBI::Relationship';

sub remap_arguments {
    my ($proto, $class, $accessor, $f_class, $f_key, $args) = @_;
    
    my %on_delete_beh = ( 'cascade'  => 1,
			  'set-null' => 1,
			  'restrict' => 1,
			  );
    
    return $class->_croak("e_has_many needs an accessor name") unless $accessor;
    return $class->_croak("e_has_many needs a foreign class")  unless $f_class;
    $class->can($accessor)
	and return $class->_carp("$accessor method already exists in $class\n");
    
    my @f_method = ();
    if (ref $f_class eq "ARRAY") {
	($f_class, @f_method) = @$f_class;
    }
    $class->_require_class($f_class);
    
    if (ref $f_key eq "HASH") {    # didn't supply f_key, this is really $args
	$args  = $f_key;
	$f_key = "";
    }
    
    $f_key ||= do {
	my $meta = $f_class->meta_info('has_a');
	my ($col) = grep $meta->{$_}->foreign_class eq $class, keys %$meta;
	$col || $class->table_alias;
    };

    if (ref $f_key eq "ARRAY") {
	return $class->_croak("Multi-column foreign keys not supported")
	    if @$f_key > 1;
	$f_key = $f_key->[0];
    }
    
    $args ||= {};
    $args->{mapping}     = \@f_method;
    $args->{foreign_key} = $f_key;
    $args->{order_by} ||= $args->{sort};    
    warn "sort argumemt to has_many deprecated in favour of order_by"
	if $args->{sort};             

    # Make 'cascade' the default on_delete behaviour
    $args->{on_delete} ||= "cascade";
    
    unless ( exists $on_delete_beh{$args->{on_delete}} ){
	return $class->_croak("Unknown on_delete behavior: $args->{on_delete}");
    }
    
    return ($class, $accessor, $f_class, $args);
}

sub _set_up_class_data {
    my $self = shift;
    $self->class->_extend_class_data(
				     __hasa_list => $self->foreign_class => $self->args->{foreign_key});
    $self->SUPER::_set_up_class_data;
}

sub triggers {
    my $self = shift;
    if ($self->args->{on_delete} eq "restrict"){
	return (
		before_delete => sub {
		    if ( scalar  $self->foreign_class->search($self->args->{foreign_key} => shift->id) ){
			return $self->class->_croak("Deletion restricted for referential integrity");
		    }
		});
	
    }elsif ($self->args->{on_delete} eq "set-null"){
	return (
		before_delete => sub {
		    foreach ( $self->foreign_class->search($self->args->{foreign_key} => shift->id) ){
			$_->set($self->args->{foreign_key}, 0);
			$_->update;
		    }
		});
    }elsif ($self->args->{on_delete} eq "cascade"){
	return (
		before_delete => sub {
		    $self->foreign_class->search($self->args->{foreign_key} => shift->id)
			->delete_all;
		});
    }
}

sub methods {
    my $self     = shift;
    my $accessor = $self->accessor;
    return (
	    $accessor          => $self->_e_has_many_method,
	    "add_to_$accessor" => $self->_method_add_to,
	    );
}

sub _method_add_to {
    my $self     = shift;
    my $accessor = $self->accessor;
    return sub {
	my ($self, $data) = @_;
	my $class = ref $self
	    or return $self->_croak("add_to_$accessor called as class method");
	return $self->_croak("add_to_$accessor needs data")
	    unless ref $data eq "HASH";
	
	my $meta = $class->meta_info(e_has_many => $accessor);
	my ($f_class, $f_key, $args) =
	    ($meta->foreign_class, $meta->args->{foreign_key}, $meta->args);
	$data->{$f_key} = $self->id;
	$f_class->create($data);
    };
}

sub _e_has_many_method {
    my $self       = shift;
    my $run_search = $self->_hm_run_search;
    my @mapping    = @{ $self->args->{mapping} } or return $run_search;
    return sub {
	return $run_search->(@_)->set_mapping_method(@mapping)
	    unless wantarray;
	my @ret = $run_search->(@_);
	foreach my $meth (@mapping) { @ret = map $_->$meth(), @ret }
	return @ret;
    }
}

sub _hm_run_search {
    my $self = shift;
    my ($class, $accessor) = ($self->class, $self->accessor);
    return sub {
	my ($self, @search_args) = @_;
	my $meta = $class->meta_info(e_has_many => $accessor);
	my ($f_class, $f_key, $args) =
	    ($meta->foreign_class, $meta->args->{foreign_key}, $meta->args);
	if (ref $self) {    # For $artist->cds
	    unshift @search_args, ($f_key => $self->id);
	    push @search_args, { order_by => $args->{order_by} }
	    if defined $args->{order_by};
	    return $f_class->search(@search_args);
	} else {            # For Artist->cds
	    # Cross-table join as class method
	    # This stuff is highly experimental and will probably change beyond
	    # recognition. Use at your own risk...
	    my %kv = @search_args;
	    my $query = Class::DBI::Query->new({ owner => $f_class });
	    $query->kings($class, $f_class);
	    $query->add_restriction(sprintf "%s.%s = %s.%s",
				    $f_class->table_alias, $f_key, $class->table_alias,
				    $class->primary_column);
	    $query->add_restriction("$_ = ?") for keys %kv;
	    my $sth = $query->run(values %kv);
	    return $f_class->sth_to_objects($sth);
	}
    };
}

1;

__END__

=head1 NAME

     Class::DBI::Relationship::eHasMany - Extended (or Enhanced) HasMany Relationship Class   

=head1 SYNOPSIS

    In your application base class:

     __PACKAGE__->add_relationship_type(
        e_has_many   => "Class::DBI::Relationship::eHasMany",
	       );

=head1 DESCRIPTION
    
     eHasMany is basically the same HasMany relationship included in Class::DBI, with the
     addition of the argument "on_delete", which defines three behaviors at deletion time:
    
             'restrict'
             'cascade'
             'set-null'

     This mimics what several DBs offer, without the need to define it at the DB level, 
     thus losing DB independence.
    
     The current (0.96) only option is _no_cascade_delete, which is both limited and 
     nonoptimal, because foreign keys would keep pointing to nonexistent object ids.

=head1 CURRENT AUTHOR
    
    Carlos Vicente <cvicente@uoregon.edu> (modified Tony Bowden's HasMany)
    
    This functionality was first suggested by Tim Bunce in the CDBI mailing list.

        http://groups.kasei.com/mail/arc/cdbi-talk/2003-02/msg00142.html

=head1 LICENSE

     This library is free software; you can redistribute it and/or modify
     it under the same terms as Perl itself.

=head1 SEE ALSO

     L<Class::DBI::Relationship>

