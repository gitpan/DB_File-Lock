#
# DB_File::Lock
#
# by David Harris <dharris@drh.net>
#
# Copyright (c) 1999-2000 David R. Harris. All rights reserved. 
# This program is free software; you can redistribute it and/or modify it 
# under the same terms as Perl itself. 
#

package DB_File::Lock;

require 5.004;

use strict;
use vars qw($VERSION @ISA $locks);

@ISA = qw(DB_File);
$VERSION = '0.01';

use DB_File ();
use Fcntl qw(:flock O_RDWR O_CREAT);
use Carp qw(croak carp verbose);
use Symbol ();

# import function can't be inherited, so this magic required
sub import
{
	my $ourname = shift;
	my @imports = @_; # dynamic scoped var, still in scope after package call in eval
	my $module = caller;
	my $calling = $ISA[0];
	eval " package $module; import $calling, \@imports; ";
}

sub TIEHASH
{
	my $package = shift;

	## There are two ways of passing data defined by DB_File

	my $lock_data;
	my @dbfile_data;

	if ( @_ == 5 ) {
		$lock_data = pop @_;
		@dbfile_data = @_;
	} elsif ( @_ == 2 ) {
		$lock_data = pop @_;
		@dbfile_data = @{$_[0]};
	} else {
		croak "invalid number of arguments";
	}

	## Decipher the lock_data

	my $mode;
	my $nonblocking   = 0;
	my $lockfile_name = $dbfile_data[0] . ".lock";;
	my $lockfile_mode;

	if ( lc($lock_data) eq "read" ) {
		$mode = "read";
	} elsif ( lc($lock_data) eq "write" ) {
		$mode = "write";
	} elsif ( ref($lock_data) eq "HASH" ) {
		$mode = lc $lock_data->{mode};
		croak "invalid mode ($mode)" if ( $mode ne "read" and $mode ne "write" );
		$nonblocking = $lock_data->{nonblocking};
		$lockfile_name = $lock_data->{lockfile_name} if ( defined $lock_data->{lockfile_name} );
		$lockfile_mode = $lock_data->{lockfile_mode};
	} else {
		croak "invalid lock_data ($lock_data)";
	}

	## Determine the mode of the lockfile, if not given

	# THEORY: if someone can read or write the database file, we must allow 
	# them to read and write the lockfile.

	if ( not defined $lockfile_mode ) {
		$lockfile_mode = 0600; # we must be allowed to read/write lockfile
		$lockfile_mode |= 0060 if ( $dbfile_data[2] & 0060 );
		$lockfile_mode |= 0006 if ( $dbfile_data[2] & 0006 );
	 }

	## Open the lockfile, lock it, and open the database

	my $lockfile_fh = Symbol::gensym();
	my $saved_umask = umask(0000) if ( umask() & $lockfile_mode );
	sysopen($lockfile_fh, $lockfile_name, O_RDWR|O_CREAT, $lockfile_mode)
		or croak "could not open lockfile ($lockfile_name)";
	umask($saved_umask) if ( defined $saved_umask );

	my $flock_flags = ($mode eq "write" ? LOCK_EX : LOCK_SH) | ($nonblocking ? LOCK_NB : 0);
	if ( not flock $lockfile_fh, $flock_flags ) {
		close $lockfile_fh;
		return undef if ( $nonblocking );
		croak "could not flock lockfile";
	}

	my $self = $package->SUPER::TIEHASH(@_);

	## Store the info for the DESTROY function

	my $id = "" . $self;
	$id =~ s/^[^=]+=//; # remove the package name in case re-blessing occurs
	$locks->{$id} = $lockfile_fh;

	## Return the object

	return $self;
}

sub DESTROY
{
	my $self = shift;

	my $id = "" . $self;
	$id =~ s/^[^=]+=//;
	my $lockfile_fh = $locks->{$id};
	delete $locks->{$id};

	$self->SUPER::DESTROY(@_);

	# un-flock not needed, as we close here
	close $lockfile_fh;
}





1;
__END__

=head1 NAME

DB_File::Lock - Locking with flock wrapper for DB_File

=head1 SYNOPSIS

 use DB_File::Lock;

 $locking = "read";
 $locking = "write";
 $locking = {
     mode            => "read",
     nonblocking     => 0,
     lockfile_name   => "/path/to/shared.lock",
     lockfile_mode   => 0600,
 };

 [$X =] tie %hash,  'DB_File::Lock', [$filename, $flags, $mode, $DB_HASH], $locking;
 [$X =] tie %hash,  'DB_File::Lock', $filename, $flags, $mode, $DB_BTREE, $locking;
 [$X =] tie @array, 'DB_File::Lock', $filename, $flags, $mode, $DB_RECNO, $locking;

 ...use the same way as DB_File for the rest of the interface...

=head1 DESCRIPTION

This module servers as a wrapper which adds locking to the DB_File
module. One new argument is added to the tie command which specifies
the locking desired. The C<$locking> argument may be either a string
to specify locking for read or write, or a hash which can specify more
information about the lock and how the lockfile is to be created.

The filename used for the lockfile defaults to "$filename.lock" (the
filename of the DB_File with ".lock" appended). Using the hash form of
the locking information, one can specify their own lock file with the
"lockfile_name" hash key. This is useful for locking multiple resources
with the same lockfiles.

The "nonblocking" hash key determines if the flock call on the lockfile
should block waiting for a lock, or if it should return failure if a
lock can not be immediately attained. If "nonblocking" is set and a lock
can not be attained, the tie command will fail.  Currently, I'm not sure
how to differentiate this between a failure form the DB_File layer.

The "lockfile_mode" hash key determines the mode for the sysopen call
in opening the lockfile. The default mode is to allow anyone that can
read or write the DB_File permission to read and write the lockfile.
(This is because some systems may require that one have write access
to a file to lock it for reading, I understand.)  The umask will not be
applied to this mode.

Note: One may import the same values from DB_File::Lock as one may import
from DB_File.


=head1 AUTHOR

David Harris <dharris@drh.net>

Helpful insight from Stas Bekman <sbekman@iil.intel.com>

=head1 SEE ALSO

DB_File(3).

=cut
