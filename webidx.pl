#!/usr/bin/perl
use File::Basename qw(dirname);
use vars qw($VERSION);

BEGIN {
    push(@INC, dirname(__FILE__).'/lib');
    require App::webidx;
}

exit(App::webidx->main(@ARGV));

=pod

=head1 SYNOPSIS

    webidx [-x FILE [-x FILE2 [...]]] [--xP PATTERN [--xP PATTERN2 [...]]] [-o ORIGIN] [-z] [DIRECTORY] [DBFILE]

This will cause all HTML files in C<DIRECTORY> to be indexed, and the resulting database written to C<DBFILE>. The supported options are:

=over

=item * C<-x FILE> specifies a file to be excluded. May be specified multiple times.

=item * C<--xP PATTERN> specifies a pattern of folders and files to be excluded. May be specified multiple times.

=item * C<-o ORIGIN> specifies a base URL which will be prepended to the filenames (once C<DIRECTORY> has been removed).

=item C<-z> specifies that the database file should be compressed once generated. If specified, the database will be at C<DBFILE.gz>.

=item * C<DIRECTORY> is the directory to be indexed, defaults to the current working directory.

=item * C<DBFILE> is the location where the database should be written. if not specified, defaults to C<DIRECTORY/index.db>.

=back

=cut
