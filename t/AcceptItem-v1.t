#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 1;
use Test::Mojo;

use NCIPTest;

# From Koha
use Koha::Database;
use Koha::Holds;
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

my %koha_config;
NCIPTest::set_config( $plugin, { koha => \%koha_config } );

my $t = Test::Mojo->new('Koha::REST::V1');

my $dom;

my $patron_category = $builder->build(
    {
        source => 'Category',
        value  => {
            category_type                 => 'P',
            enrolmentfee                  => 0,
            BlockExpiredPatronOpacActions => -1,    # Pick the pref value
        }
    }
);

my $library = Koha::Libraries->search()->next();

my $patron_1 = $builder->build_object(
    {
        class => 'Koha::Patrons',
        value => {
            branchcode   => $library->id,
            categorycode => $patron_category->{categorycode},
            dateexpiry   => '2032-12-31',
            firstname    => 'Kyle',
            surname      => 'Hall',
            userid       => 'khall',
        }
    }
);

subtest 'Test AcceptItem with valid user' => sub {
    plan tests => 15;

    $koha_config{framework} = 'FA';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $ncip_message = NCIPTest::render_fixture(
        'v1/AcceptItem.xml',
        {
            patron_cardnumber => $patron_1->cardnumber,
            pickup_location   => $library->branchcode,
            item_barcode      => 'NCIP-V1-ITEM-1',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{ResponseHeader}->{FromAgencyId}->{UniqueAgencyId}->{Value}->{text},
        $library->branchcode,
	'AcceptItemResponse FromAgencyId is the ToAgencyId of the request',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{ResponseHeader}->{ToAgencyId}->{UniqueAgencyId}->{Value}->{text},
	'ILL SYSTEM',
	'AcceptItemResponse ToAgencyId is the FromAgencyId of the request',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{UniqueRequestId}->{UniqueAgencyId}->{Value}->{text},
        $library->branchcode,
	'AcceptItemResponse UniqueRequestId gives correct UniqueAgencyId',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{UniqueRequestId}->{RequestIdentifierValue}->{text},
	'NCIP-V1-ITEM-1',
	'AcceptItemResponse UniqueRequestId gives the new item barcode',
    );

    my $item = Koha::Items->find({ barcode => 'NCIP-V1-ITEM-1' });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    my $b = $item->biblio;
    is( $b->frameworkcode, 'FA', 'Bib has correct framework code' );
    is( $b->copyrightdate, '2001', 'Bib has correct copyright date' );
    is( $b->author, 'Guertin, Mike.', 'Bib has correct author' );
    is( $b->title, 'Precision framing', 'Bib has correct title' );

    my $bi = $item->biblioitem;
    is( $bi->publishercode, 'Taunton Press ; Publishers Group West [distributor]', 'Bib has correct publisher' );

    is( $item->itemcallnumber, '694.2 .G84 2001', 'Item callnumber is taken from the CallNumber in the message' );
    is( $item->homebranch, $library->branchcode, 'Item homebranch is the ToAgencyId of the request' );

    my $hold = Koha::Holds->search({ itemnumber => $item->itemnumber })->next;
    is( ref($hold), 'Koha::Hold', 'Found hold for the created item' );
    is( $hold->borrowernumber, $patron_1->borrowernumber, 'Hold belongs to the correct patron' );
    is( $hold->found, 'W', 'Hold was trapped, hold is waiting' );
};

$schema->storage->txn_rollback;
