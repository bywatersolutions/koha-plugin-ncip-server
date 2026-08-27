#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 1;
use Test::Mojo;

use NCIPTest;

# From NCIP
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Const;

# From Koha
use Koha::Database;
use t::lib::Mocks;
use t::lib::TestBuilder;

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;
my $builder = t::lib::TestBuilder->new;
my $dbh     = C4::Context->dbh;

# Start transaction
$dbh->{RaiseError} = 1;

my $plugin = NCIPTest::install_plugin();

my %koha_config = ();
NCIPTest::set_config( $plugin, { koha => \%koha_config } );

my $t = Test::Mojo->new('Koha::REST::V1');

my $dom;

subtest 'Test LookupVersion returns the supported versions' => sub {
    plan tests => 2;

    my $ncip_message = NCIPTest::render_fixture( 'v2/LookupVersion.xml', {} );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    my $versions = $dom->{NCIPMessage}->{LookupVersionResponse}->{VersionSupported};

    # XML::Hash returns an arrayref when there is more than one element
    my @supported = map { $_->{text} =~ s/^\s+|\s+$//gr } @{$versions};

    is(
        scalar @supported,
        scalar( () = Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Const::SUPPORTED_VERSIONS ),
        'LookupVersionResponse returns one VersionSupported per supported version'
    );
    ok(
        ( grep { $_ eq 'http://www.niso.org/schemas/ncip/v2_02/ncip_v2_02.xsd' } @supported ),
        'LookupVersionResponse advertises the NCIP v2.02 schema'
    );
};

$schema->storage->txn_rollback;
