#!/usr/bin/perl
use Cwd qw(abs_path);
use Getopt::Long qw(:config bundling auto_version auto_help);
use DBD::SQLite;
use DBI;
use File::Basename qw(basename);
use File::Glob qw(:bsd_glob);
use HTML::Parser;
use IPC::Open2;
use IO::File;
use List::Util qw(uniq none any);
use feature qw(say);
use open qw(:encoding(utf8));
use strict;
use utf8;
use vars qw($VERSION);

$VERSION = 0.02;

#
# parse command line options
#
my (@exclude, @excludePattern, $compress, $origin);
die() unless (GetOptions(
    'exclude|x=s'           => \@exclude,
    'excludePattern|xP=s'   => \@excludePattern,
    'compress|z'            => \$compress,
    'origin|o=s'            => \$origin
));

@exclude = map { abs_path($_) } @exclude;

#
# determine the source directory and the database filename
#
my $dir     = abs_path(shift(@ARGV) || '.');
my $dbfile  = abs_path(shift(@ARGV) || $dir.'/webidx.db');

#
# initialise the database
#
unlink($dbfile) if (-e $dbfile);
my $db = DBI->connect('dbi:SQLite:dbname='.$dbfile, '', '', {
    'PrintError' => 1,
    'RaiseError' => 1,
    'AutoCommit' => 0,
});

#
# a list of words we want to exclude
#
my @common = qw(be and of a in to it i for he she on do at but from that not by or as can who get if my as up so me the are we was is);

#
# this is a map of filename => page title
#
my $titles = {};

#
# this is map of word => page
#
my $index = {};

#
# scan the source directory
#

say 'scanning ', $dir;

scan_directory($dir);

#
# generate the database
#

say 'finished scan, generating index';

$db->do(qq{BEGIN});

$db->do(qq{CREATE TABLE `pages` (`id` INTEGER PRIMARY KEY, `url` TEXT, `title` TEXT)});
$db->do(qq{CREATE TABLE `words` (`id` INTEGER PRIMARY KEY, `word` TEXT)});
$db->do(qq{CREATE TABLE `index` (`id` INTEGER PRIMARY KEY, `word_id` INT, `page_id` INT, `hits` INT)});

my $word_sth    = $db->prepare(qq{INSERT INTO `words` (`word`) VALUES (?)});
my $page_sth    = $db->prepare(qq{INSERT INTO `pages` (`url`, `title`) VALUES (?, ?)});
my $index_sth   = $db->prepare(qq{INSERT INTO `index` (`word_id`, `page_id`, `hits`) VALUES (?, ?, ?)});

my $word_ids = {};
my $page_ids = {};

#
# for each word...
#
foreach my $word (keys(%{$index})) {

    #
    # insert an entry into the words table (if one doesn't already exist)
    #
    if (!defined($word_ids->{$word})) {
        $word_sth->execute($word);
        $word_ids->{$word} = $db->last_insert_id;
    }

    #
    # for each page...
    #
    foreach my $page (keys(%{$index->{$word}})) {
        my $hits = $index->{$word}->{$page};

        #
        # clean up the page title by removing leading and trailing whitespace
        #
        my $title = $titles->{$page};
        $title =~ s/^[ \s\t\r\n]+//g;
        $title =~ s/[ \s\t\r\n]+$//g;

        #
        # remove the directory
        #
        $page =~ s/^$dir//;

        #
        # prepend the origin
        #
        $page = $origin.$page if ($origin);

        #
        # insert an entry into the pages table (if one doesn't already exist)
        #
        if (!defined($page_ids->{$page})) {
            $page_sth->execute($page, $title);
            $page_ids->{$page} = $db->last_insert_id;
        }

        #
        # insert an index entry
        #
        $index_sth->execute($word_ids->{$word}, $page_ids->{$page}, $hits) || die();
    }
}

$db->do(qq{COMMIT});

$db->disconnect;

if ($compress) {
    say 'compressing database...';
    open2(undef, undef, qw(gzip -f -9), $dbfile);
}

say 'done';

exit;

#
# reads the contents of a directory: all HTML files are indexed, all directories
# are scanned recursively. symlinks to directories are *not* followed
#
sub scan_directory {
    my $dir = shift;

    foreach my $file (map { abs_path($_) } bsd_glob(sprintf('%s/*', $dir))) {
        if (-d $file) {

            next if (any { $file =~ m/\Q$_/i } @excludePattern);

            #
            # directory, scan it
            #
            scan_directory($file);

        } elsif ($file =~ /\.html?$/i) {
            #
            # HTML file, index it
            #
            index_html($file);

        }
    }
}

#
# index an HTML file
#
sub index_html {
    my $file = shift;

    return if (any { $_ eq $file } @exclude) || (any { $file =~ m/\Q$_/i } @excludePattern);

    my $currtag;
    my $text;
    my $noindex;
    my $parser = HTML::Parser->new(
        #
        # text handler
        #
        'text_h' => [sub {
            if ('title' eq $currtag) {
                #
                # <title> tag, which goes into the $titles hashref
                #
                $titles->{$file} = shift;

            } else {
                #
                # everything else, which just gets appended to the $text string
                #
                $text .= " ".shift;

            }
        }, qq{dtext}],

        #
        # start tag handler
        #
        'start_h' => [sub {
            #
            # set $noindex if a <meta> tag is found
            #
            $noindex = 1 if ('meta' eq $_[0] && 'robots' eq $_[1]->{'name'} && $_[1]->{'content'} =~ m/noindex/i;

            #
            # add the alt attributes of images, and any title attributes found
            #
            $text .= " ".$_[1]->{'alt'} if (lc('img') eq $_[0]);
            $text .= " ".$_[1]->{'title'} if (defined($_[1]->{'title'}));

            $currtag = $_[0];
        }, qq{tag,attr}],

        #
        # end tag handler
        #
        'end_h' => [sub {
            undef($currtag);
        }, qq{tag}],
    );

    $parser->unbroken_text(1);

    #
    # we expect these elements contain text we don't want to index
    #
    $parser->ignore_elements(qw(h1 script style header nav footer));

    #
    # open the file, being careful to ensure it's treated as UTF-8
    #
    my $fh = IO::File->new($file);
    $fh->binmode(qq{:utf8});

    #
    # parse
    #
    $parser->parse_file($fh);
    $fh->close;

    return if ($noindex);

    my @words = grep { my $w = $_ ; none { $w eq $_ } @common } # filter out common words
                grep { /\w/ }                                   # filter out strings that don't contain at least one word character
                map {
                    $_ =~ s/^[^\w]+//g;                         # remove leading non-word characters
                    $_ =~ s/[^\w]+$//g;                         # remove trailing non-word characters
                    $_;
                }
                split(/[\s\r\n]+/, lc($text));                  # split by whitespace

    foreach my $word (@words) {
        #
        # increment the counter for this word/file
        #
        $index->{$word}->{$file}++;
    }
}

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
