#!/usr/local/bin/perl
# Xcode auto-versioning script for Subversion by Axel Andersson
# Updated for git by Marcus S. Zarra and Matt Long
# Even further revised for automatic commits and nice version numbers by Stephen Riehm

use strict;
use warnings;
use POSIX   qw( strftime );

$ENV{'PATH'} =~ s#^#/usr/local/bin:#;

my $timestamp = strftime( "%Y-%m-%d %H:%M:%S %z", localtime() );
my $git_dir   = qx{ git rev-parse --git-dir };
chomp( $git_dir );
exit unless $git_dir;
$git_dir .= '/..';

# no new version will be created if nothing has changed
# edit .git/info/excludes to keep junk out
system( qw{ git add . } );

# commit the current state of all files being used for building
system( "git", "commit", "-a", "-m", "automatic build commit" );

# git-describe returns the latest tag, the number of patches since that tag, and a commit-ID
my $git_description = qx{ git describe --long };
my ( $release, $patch, $commit ) = ( $git_description =~ /([^-]+)-(\d+)-g(\w+)/ );
$release .= ".${patch}" if $patch;
if( ! $release )
    {
    my @cmd = qw{ git log -1 --abbrev-commit --pretty }, "format=%h %ci";
    my $git_commit = qx{ @cmd };
    $release = "PRE-RELEASE $git_commit";
    }

if( open( VERSION, ">", "$git_dir/version.txt" ) )
    {
    print VERSION "$release\n";
    close( VERSION );
    }

system( "git", "log", ">", "$git_dir/CHANGELOG" );
