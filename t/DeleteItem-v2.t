#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 2;
use Test::Mojo;

use NCIPTest;

# From Koha
use Koha::Database;
use Koha::Items;
use Koha::Libraries;
use Koha::Patrons;
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

my $library = Koha::Libraries->search()->next();

my $librarian = $builder->build_object( { class => 'Koha::Patrons', value => { branchcode => $library->id } } );
$koha_config{userenv_borrowernumber} = $librarian->id;
NCIPTest::set_config( $plugin, { koha => \%koha_config } );

subtest 'Test DeleteItem with a valid item' => sub {
    plan tests => 2;

    my $item    = $builder->build_sample_item( { library => $library->id } );
    my $barcode = $item->barcode;

    my $ncip_message = NCIPTest::render_fixture(
        'v2/DeleteItem.xml',
        {
            item_identifier => $barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{DeleteItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $barcode,
        'DeleteItemResponse returns correct item barcode'
    );
    is(
        Koha::Items->find( { barcode => $barcode } ),
        undef,
        'Item has actually been deleted from the catalog'
    );
};

subtest 'Test DeleteItem with an invalid item' => sub {
    plan tests => 4;

    my $barcode = 'This Is A Barcode That Does Not Exist';

    my $ncip_message = NCIPTest::render_fixture(
        'v2/DeleteItem.xml',
        {
            item_identifier => $barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{DeleteItemResponse}->{Problem}->{ProblemType}->{text},
        'Unknown Item',
        'DeleteItemResponse returns correct problem type for an unknown item'
    );
    is(
        $dom->{NCIPMessage}->{DeleteItemResponse}->{Problem}->{ProblemDetail}->{text},
        'Item is not known.',
        'DeleteItemResponse returns correct problem detail for an unknown item'
    );
    is(
        $dom->{NCIPMessage}->{DeleteItemResponse}->{Problem}->{ProblemElement}->{text},
        'UniqueItemIdentifier',
        'DeleteItemResponse returns correct problem element for an unknown item'
    );
    is(
        $dom->{NCIPMessage}->{DeleteItemResponse}->{Problem}->{ProblemValue}->{text},
        $barcode,
        'DeleteItemResponse returns correct problem value for an unknown item'
    );
};

$schema->storage->txn_rollback;
