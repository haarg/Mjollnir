package Mjollnir::DB;
use strict;
use warnings;
use 5.010;

our $VERSION = 0.03;

use File::ShareDir ();
use File::HomeDir  ();
use File::Path     ();
use File::Spec     ();
use DBI;
use DBD::SQLite;
use constant DB_SCHEMA_VERSION => 7;

@Mjollnir::DB::ISA = qw(DBI);
@Mjollnir::DB::db::ISA = qw(DBI::db);
@Mjollnir::DB::st::ISA = qw(DBI::st);

sub db_filename {
    my $data_dir = File::HomeDir->my_data('Mjollnir');
    my $db_file  = File::Spec->catfile( $data_dir, '.mjollnir', 'mjollnir.db' );
    return $db_file;
}

sub new {
    my $class = shift;
    my $options  = (@_ == 1 && ref $_[0]) ? shift : { @_ };

    my $db_file = $options->{db_file} // $class->db_filename;
    my $create = !-e $db_file;
    if ($create) {
        my $dir = File::Spec->catpath((File::Spec->splitpath($db_file))[0,1], '');
        if (! -e $dir) {
            File::Path::make_path($dir);
        }
        my $data_dir = File::ShareDir::dist_dir('Mjollnir');
        my $old_db_file  = File::Spec->catfile( $data_dir, 'mjollnir.db' );
        if (-e $old_db_file) {
            require File::Copy;
            File::Copy::move($old_db_file, $db_file);
            chmod 0644, $db_file;
            $create = 0;
        }
    }
    my $self = $class->connect( 'dbi:SQLite:' . $db_file, undef, undef, {
        PrintError => 0,
        RaiseError => 1,
    });
    if ($create) {
        $self->_create;
        $self->do('PRAGMA user_version = ' . DB_SCHEMA_VERSION);
    }
    else {
        my $sql_dir = File::Spec->catdir(File::ShareDir::dist_dir('Mjollnir'), 'sql');
        my $current_db_version = $self->selectrow_array('PRAGMA user_version');
        $current_db_version ||= 0;
        if ($current_db_version == DB_SCHEMA_VERSION) {
            return $self;
        }
        elsif ($current_db_version < DB_SCHEMA_VERSION) {
            for my $step ($current_db_version .. DB_SCHEMA_VERSION - 1) {
                my $next_step = $step + 1;
                my $sql_script = File::Spec->catfile($sql_dir, 'upgrade-' . $step . '-' . $next_step . '.sql');
                my $pl_script = File::Spec->catfile($sql_dir, 'upgrade-' . $step . '-' . $next_step . '.pl');
                if (!-e $sql_script && !-e $pl_script) {
                    die "Impossible to perform schema upgrade!\n";
                }
                $self->{logger}->("Upgrading DB Schema to version $next_step...\n");
                if (-e $sql_script) {
                    $self->_run_sql_script($sql_script);
                }
                if (-e $pl_script) {
                    $self->_run_pl_script($pl_script);
                }
                $self->do("PRAGMA user_version = $next_step");
            }
        }
        else {
            die;
        }
    }

    return $self;
}

package Mjollnir::DB::db;

sub _run_sql_script {
    my $self = shift;
    my $filename = shift;
    open my $fh, '<', $filename
        or die "Can't open $filename: $!";
    my $sql = do { local $/; <$fh> };
    close $fh;
    my @sql = grep { /\S/ } split /;$/msx, $sql;
    for my $stmt (@sql) {
        eval { $self->do($stmt) } or die "$@: $stmt\n";
    }
    return 1;
}

sub _run_pl_script {
    my $self = shift;
    my $filename = shift;
    package main;
    local $::dbh = $self;
    do $filename;
    die $@ if $@;
    return 1;
}

sub _create {
    my $self = shift;
    my $filename = File::ShareDir::dist_file('Mjollnir', 'sql/create.sql');
    return $self->_run_sql_script($filename);
}

sub get_ip_bans {
    my $self = shift;

    my @ips = map {@$_} @{
        $self->selectall_arrayref('SELECT ip FROM ip_bans ORDER BY timestamp DESC')
    };
    return \@ips;
}

sub check_banned_ip {
    my $self = shift;
    my $ip   = shift;

    my $match =
        $self->selectrow_array( 'SELECT COUNT(*) FROM ip_bans WHERE ip = ?',
            {}, $ip, );
    return $match;
}

sub clear_ip_bans {
    my $self = shift;

    $self->do('DELETE FROM ip_bans');
    return 1;
}

sub add_name_ban {
    my $self = shift;
    my $name_pattern = shift;

    $self->do( 'INSERT OR REPLACE INTO name_bans (name_pattern, timestamp) VALUES (?, ?)',
        {}, $name_pattern, time );
}

sub remove_name_ban {
    my $self = shift;
    my $name_pattern = shift;

    $self->do( 'DELETE FROM name_bans WHERE name_pattern = ?',
        {}, $name_pattern );
    return 1;
}

sub get_name_bans {
    my $self = shift;

    my @names = map {@$_} @{
        $self->selectall_arrayref('SELECT name_pattern FROM name_bans ORDER BY name_pattern ASC')
    };
    return \@names;
}

sub check_banned_name {
    my $self = shift;
    my $name = shift;

    my $match = $self->selectrow_array('SELECT COUNT(*) FROM name_bans WHERE ? REGEXP name_pattern', {}, $name);

    return $match;
}

1;

__END__

=head1 NAME

Mjollnir::DB - Database storage for Mjollnir

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
