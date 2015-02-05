package fingerbank::Base::CRUD;

=head1 NAME

fingerbank::Base::CRUD

=head1 DESCRIPTION

Basic CRUD methods related to manipulating different fingerbank data.

Stuff in this class is meant to be overridden on a class basis if there's need for it.

=cut

use strict;
use warnings;

use Moose;
use namespace::autoclean;
use POSIX;

use fingerbank::DB;
use fingerbank::Error qw(is_error is_success);
use fingerbank::Log qw(get_logger);

=head1 HELPERS

=head2 _parseClassName

Parse the class name based on the caller package name

=cut

sub _parseClassName {
    my ( $self ) = @_;

    my $className = $self;
    $className =~ s#^.*:##;

    return $className;
}

=head2 _getTableID

=cut

sub _getTableID {
    my ( $self, $table ) = @_;

    my $db = fingerbank::DB->connect('Local');
    my $resultset = $db->resultset('TablesIDs')->first;

    $table = lc($table);
    return $resultset->$table;
}

=head2 _incrementTableID

=cut

sub _incrementTableID {
    my ( $self, $table ) = @_;

    my $db = fingerbank::DB->connect('Local');

    # Get current ID before incrementing it
    my $resultset = $db->resultset('TablesIDs')->first;
    $table = lc($table);
    my $id = $resultset->$table;

    # Increment the ID and update the table
    $id ++;
    $db->resultset('TablesIDs')->update({ $table => $id });
}


=head1 METHODS

=head2 create

Create a new entry in the 'Local' database.

ID will be automatically generated since we need to manage them by prefixing L.

Expects an hashref as args.

HTTP 200 OK status code is returned along with the newly created entry in case of success.

HTTP 500 INTERNAL SERVER ERROR status code is returned along with a status message in case of failure (unable to create).

=cut

sub create {
    my ( $self, $args ) = @_;
    my $logger = get_logger;

    my $className = $self->_parseClassName;
    my $return = {};

    my $entry_id = "L" . $self->_getTableID($className);    # Local entries IDs are prefixed by L

    $logger->debug("Attempting to create a new '$className' entry with ID '$entry_id' in schema 'Local'");

    # Prepare arguments for entry creation
    $args->{id} = $entry_id;    # We need to override the ID for a local one
    $args->{created_at} = strftime("%Y-%m-%d %H:%M:%S", localtime(time));   # Overriding created_at with current timestamp
    $args->{updated_at} = strftime("%Y-%m-%d %H:%M:%S", localtime(time));   # Overriding updated_at with current timestamp

    my $db = fingerbank::DB->connect('Local');
    my $resultset = $db->resultset($className)->create($args);

    # Query doesn't returned any result which means failure in this case
    if ( !defined($resultset) ) {
        my $status_msg = "Cannot create new '$className' entry with ID '$entry_id' in schema 'Local'";
        $logger->warn($status_msg);
        return ( $fingerbank::Status::INTERNAL_SERVER_ERROR, $status_msg );
    }

    # Increment table ID after successful creation
    $self->_incrementTableID($className);

    # Building the newly created resultset to be returned
    foreach my $column ( $resultset->result_source->columns ) {
        $return->{$column} = $resultset->$column;
    }

    $logger->info("Created new '$className' entry with ID '$entry_id' in schema 'Local'");

    return ( $fingerbank::Status::OK, $return );
}

=head2 read

Read a single entry by using his ID.

Expects the entry ID to be readed.

HTTP 200 OK status code is returned along with the requested entry in case of success.

HTTP 404 NOT FOUND status code is returned along with a status message in case of failure (non-existant entry).

=cut

sub read {
    my ( $self, $id ) = @_;
    my $logger = get_logger;

    my $className = $self->_parseClassName;
    my $return = {};

    # Verify if the provided ID is part of the local or upstream schema to seach accordingly
    # Local schema IDs are 'L' prefixed
    my $schema = ( lc($id) =~ /^l/ ) ? 'Local' : 'Upstream';

    $logger->debug("Looking for '$className' entry with ID '$id' in schema '$schema'");

    my $db = fingerbank::DB->connect($schema);
    my $resultset = $db->resultset($className)->find($id);

    # Query doesn't return any result
    if ( !defined($resultset) ) {
        my $status_msg = "Could not find any '$className' entry with ID '$id' in schema '$schema'";
        $logger->info($status_msg);
        return ( $fingerbank::Status::NOT_FOUND, $status_msg );
    }

    # Building the resultset to be returned
    foreach my $column ( $resultset->result_source->columns ) {
        $return->{$column} = $resultset->$column;
    }

    $logger->info("Found '$className' entry with ID '$id' in schema '$schema'");

    return ( $fingerbank::Status::OK, $return );
}

=head2 update

Update an existing entry in the 'Local' database.

Expects the entry ID to be updated and an hashref as args.

HTTP 200 OK status code is returned along with the updated entry in case of success.

HTTP 404 NOT FOUND status code is returned along with a status message in case of failure (non-existant entry).

=cut

sub update {
    my ( $self, $id, $args ) = @_;
    my $logger = get_logger;

    my $className = $self->_parseClassName;
    my $return = {};

    $logger->debug("Attempting to update '$className' entry with ID '$id' in schema 'Local'");

    # We need to update the 'updated_at' timestamp
    $args->{updated_at} = strftime("%Y-%m-%d %H:%M:%S", localtime(time));

    # Fetching current data to build the resultset from which we will then update with new data
    my $db = fingerbank::DB->connect('Local');
    my $resultset = $db->resultset($className)->find($id);

    # Query doesn't returned any result
    if ( !defined($resultset) ) {
        my $status_msg = "Could not find any '$className' entry with ID '$id' in schema 'Local'. Cannot update";
        $logger->info($status_msg);
        return ( $fingerbank::Status::NOT_FOUND, $status_msg );
    }

    # Calling update on the resultset to update it with new data
    $logger->debug("Found '$className' entry with ID '$id' in schema 'Local'. Proceed with update");
    $resultset->update($args);

    # TODO: Add validation on wheter update worked or not ?
    # TODO: Logging statement should we WARN

    # Building the updated resultset to be returned
    foreach my $column ( $resultset->result_source->columns ) {
        $return->{$column} = $resultset->$column;
    }

    $logger->info("Updated '$className' entry with ID '$id' in schema 'Local'");

    return ( $fingerbank::Status::OK, $return );
}

=head2 delete

Delete an existing entry in the 'Local' database.

Expects the entry ID to be deleted.

HTTP 200 OK status code is returned in case of success.

HTTP 404 NOT FOUND status code is returned along with a status message in case of failure (non-existant entry).

=cut

sub delete {
    my ( $self, $id ) = @_;
    my $logger = get_logger;

    my $className = $self->_parseClassName;

    $logger->debug("Attempting to delete '$className' entry with ID '$id' from schema 'Local'");

    # Fetching current data to build the resultset from which we will delete
    my $db = fingerbank::DB->connect('Local');
    my $resultset = $db->resultset($className)->find($id);

    # Query doesn't returned any result
    if ( !defined($resultset) ) {
        my $status_msg = "Could not find any '$className' entry with ID '$id' in schema 'Local'. Cannot delete";
        $logger->info($status_msg);
        return ( $fingerbank::Status::NOT_FOUND, $status_msg );
    }

    # Calling delete on the resultset to delete it from the database
    $logger->debug("Found '$className' entry with ID '$id' in schema 'Local'. Proceed with delete");
    $resultset->delete;

    # TODO: Add validation on wheter delete worked or not ?
    # TODO: Logging statement should we WARN

    $logger->info("Deleted '$className' entry with ID '$id' in schema 'Local'");

    return $fingerbank::Status::OK;
}

=head2 search

Advanced search

=head3 Usage

First arguement is an array ref of the arguments expected by the L<DBIx::Class::ResultSet> search function

Followed by the schema you wish to search

    my ($status, $resultSets_or_errormsg) = $obj->search($arr_ref_of_search_option);

    my ($status, $resultSets_or_errormsg) = $obj->search($arr_ref_of_search_option, $optional_schema);

    my ($status, $resultSets_or_errormsg) = $obj->search([{ col1 => val1}], 'Local');

=head3 Return

Returns a fingerbank::Status code and an array ref of the result set or status message

If the status is not OK the results is a status message

    status code - fingerbank::Status

    array ref of result sets or error message

=cut

sub search {
    my ( $self, $search_args, $schema ) = @_;
    my $logger = get_logger;

    my $className = $self->_parseClassName;
    my @resultSets;

    # From which schema do we want the results
    my @schemas = ( defined($schema) ) ? ($schema) : @fingerbank::DB::schemas;

    foreach my $schema ( @schemas ) {
        $logger->debug("Searching '$className' entries in schema $schema");

        my $db = fingerbank::DB->connect($schema);
        my $resultset = $db->resultset($className)->search(@$search_args);

        # Empty resultset should not be pushed into the result array
        next if $resultset eq 0;

        push @resultSets,$resultset;
    }

    # Query doesn't return any result on any of the schema(s)
    unless ( @resultSets ) {
        my $status_msg = "Searching for '$className' entries in schema(s) returned an empty set";
        $logger->info($status_msg);
        return ( $fingerbank::Status::NOT_FOUND, $status_msg );
    }

    return ( $fingerbank::Status::OK, \@resultSets );
}

=head2 find

=cut

sub find {
    my ( $self, $search_args, $schema ) = @_;
    my $logger = get_logger;

    my $className = $self->_parseClassName;
    my $return;

    my ($status, $result) = $self->search($search_args, $schema);

    # There was an 'error' in the search.
    return ($status, $result) if ( is_error($status) );

    foreach my $resultset ( @$result ) {
        $return = $resultset->first;
        last if defined $return;
    }

    return ( $fingerbank::Status::OK, $return );
}

=head2 list

=cut

sub list {
    my ( $self, $schema ) = @_;
    my $logger = get_logger;

    my $className = $self->_parseClassName;
    my $return = {};

    my ($status, $result) = $self->search([], $schema);

    # There was an 'error' in the search.
    return ($status, $result) if ( is_error($status) );

    # Building the resultset to be returned
    foreach my $resultset ( @$result ) {
        while ( my $row = $resultset->next ) {
            $return->{$row->id} = $row->value;
        }
    }

    return ($fingerbank::Status::OK, $return);
}

=head2 list_paginated

Handing out a parameterized list of results.

Query optionnal parameters:

- offset: Where to being the listing from (I want 10 result starting after the sixth one). Don't forget that DBIx offset is zero based.

- nb_of_rows: The number of results

- order: asc or desc

- order_by: The field on which we should order the results

- schema: From which schema we want the results. Either 'Upstream' or 'Local'. Default to all

=cut

sub list_paginated {
    my ( $self, $query ) = @_;
    my $logger = get_logger;

    my $className = $self->_parseClassName;
    my @return;

    my ($status, $result) = $self->search([{},
        { offset => $query->{offset}, rows => $query->{nb_of_rows}, order_by => { -$query->{order} => $query->{order_by} } }], 
        $query->{schema});

    # There was an 'error' in the search.
    return ($status, $result) if ( is_error($status) );

    # Building the resultset to be returned
    foreach my $resultset ( @$result ) {
        while ( my $row = $resultset->next ) {
            my %array_row = ( 'id' => $row->id, 'value' => $row->value );
            push ( @return, \%array_row );
        }
    }

    return ($fingerbank::Status::OK, \@return);
}

=head2 count

=cut

sub count {
    my ( $self, $schema ) = @_;
    my $logger = get_logger;

    my $className = $self->_parseClassName;
    my $count;

    # From which schema do we want the results
    my @schemas = ( defined($schema) ) ? ($schema) : @fingerbank::DB::schemas;

    foreach my $schema ( @schemas ) {
        my $db = fingerbank::DB->connect($schema);
        my $nb_of_rows = $db->resultset($className)->search->count;
        $count += $nb_of_rows;
    }

    return $count;
}

=head2 clone

=cut

sub clone {
    my ( $self, $id ) = @_;
    my $logger = get_logger;

    my $className = $self->_parseClassName;

    $logger->debug("Attempting to clone '$className' entry ID '$id' in schema 'Local'");

    my $return = {};

    my $original_item = $self->read($id);
    $self->create($original_item);    
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2015 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

__PACKAGE__->meta->make_immutable;

1;