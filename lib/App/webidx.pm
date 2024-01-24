package App::webidx;
use Cwd qw(abs_path);
use DBD::SQLite;
use DBI;
use File::Basename qw(basename);
use File::Glob qw(:bsd_glob);
use Getopt::Long qw(GetOptionsFromArray :config bundling auto_version auto_help);
use HTML::Parser;
use IO::File;
use IPC::Open2;
use List::Util qw(uniq none any);
use feature qw(say);
use open qw(:encoding(utf8));
use strict;
use utf8;
use vars qw($VERSION @exclude @excludePattern $compress $origin $dir $dbfile @common $titles $index @ignore_elements $currtag $text);
use warnings;

$VERSION = '0.03';

#
# a list of words we want to exclude. Obviously this is just English, we may want to internationalize at some point
#
@common = qw(be and of a in to it i for he on do at but from that not by or as can who get if my as up so me the are we was is);

#
# we expect these elements contain text we don't want to index
#
@ignore_elements = qw(h1 script style header nav footer);

sub main {
    my ($package, @opts) = @_;

    #
    # parse command line options
    #
    die() unless (GetOptionsFromArray(
        \@opts,
        'exclude|x=s'           => \@exclude,
        'excludePattern|xP=s'   => \@excludePattern,
        'compress|z'            => \$compress,
        'origin|o=s'            => \$origin
    ));

    @exclude = map { abs_path($_) } @exclude;

    #
    # determine the source directory and the database filename
    #
    $dir = abs_path(shift(@opts) || '.');
    $dbfile = abs_path(shift(@opts) || $dir.'/webidx.db');

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
    # this is a map of filename => page title
    #
    $titles = {};

    #
    # this is map of word => page
    #
    $index = {};

    #
    # this is used to identify the current tag for any text found in the tree
    #
    $currtag = undef;

    #
    # this stores all the text found so far
    #
    $text = undef;

    #
    # scan the source directory
    #
    say 'scanning ', $dir;
    $package->scan_directory($dir);

    #
    # generate the database
    #
    say 'finished scan, generating index';

    $db->do(qq{BEGIN});

    $db->do(qq{CREATE TABLE `pages` (`id` INTEGER PRIMARY KEY, `url` TEXT, `title` TEXT)});
    $db->do(qq{CREATE TABLE `words` (`id` INTEGER PRIMARY KEY, `word` TEXT)});
    $db->do(qq{CREATE TABLE `index` (`id` INTEGER PRIMARY KEY, `word` INT, `page_id` INT)});

    my $word_sth    = $db->prepare(qq{INSERT INTO `words` (`word`) VALUES (?)});
    my $page_sth    = $db->prepare(qq{INSERT INTO `pages` (`url`, `title`) VALUES (?, ?)});
    my $index_sth   = $db->prepare(qq{INSERT INTO `index` (`word`, `page_id`) VALUES (?, ?)});

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
            my $title = $titles->{$page};

            #
            # remove the directory
            #
            $page =~ s/^$dir//;

            #
            # prepend the origin
            #
            $page = $origin.$page if ($origin);

            if (!$title) {
                $title = $page;

            } else {
                #
                # clean up the page title by removing leading and trailing whitespace
                #
                $title =~ s/^[ \s\t\r\n]+//g;
                $title =~ s/[ \s\t\r\n]+$//g;
            }

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
            $index_sth->execute($word_ids->{$word}, $page_ids->{$page}) || die();
        }
    }

    $db->do(qq{COMMIT});

    $db->disconnect;

    my $status = 0;

    if ($compress) {
        say 'compressing database...';
        my $pid = open2(undef, undef, qw(gzip -f -9), $dbfile);
        waitpid($pid, 0);
        $status = $? >> 8;
    }

    say 'done';

    return $status;
}

#
# reads the contents of a directory: all HTML files are indexed, all directories
# are scanned recursively. symlinks to directories are *not* followed
#
sub scan_directory {
    my ($package, $dir) = @_;

    foreach my $file (map { abs_path($_) } bsd_glob(sprintf('%s/*', $dir))) {
        if (-d $file) {

            next if (any { $file =~ m/\Q$_/i } @excludePattern);

            #
            # directory, scan it
            #
            $package->scan_directory($file);

        } elsif ($file =~ /\.html?$/i) {
            #
            # HTML file, index it
            #
            $package->index_html($file);

        }
    }
}

#
# index an HTML file
#
sub index_html {
    my ($package, $file) = @_;

    return if (any { $_ eq $file } @exclude) || (any { $file =~ m/\Q$_/i } @excludePattern);

    my $parser = HTML::Parser->new(
        #
        # text handler
        #
        'text_h' => [sub {
            if (defined($currtag) && 'title' eq $currtag) {
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
    $parser->ignore_elements(@ignore_elements);

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

1;
