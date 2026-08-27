#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More;
use Cwd qw(abs_path);
use File::Find;
use FindBin qw($Bin);

=head1 DESCRIPTION

Loads every module in the plugin's Koha/ tree. The vendored NCIP modules
live in the plugin namespace, so their path-derived module names are the
real package names.

=cut

my $root = abs_path("$Bin/..");

unshift( @INC, $root );
unshift( @INC, '/kohadevbox/koha/' );
unshift( @INC, '/kohadevbox/koha/misc/translator/' );
unshift( @INC, '/kohadevbox/koha/t/lib/' );

find(
    {
        bydepth  => 1,
        no_chdir => 1,
        wanted   => sub {
            my $m = $_;
            return unless $m =~ s/[.]pm$//;
            $m =~ s{^\Q$root\E/}{};
            $m =~ s{/}{::}g;
            use_ok($m) || BAIL_OUT("***** PROBLEMS LOADING FILE '$m'");
        },
    },
    "$root/Koha"
);

done_testing();
