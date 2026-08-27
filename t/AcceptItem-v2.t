#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 3;
use Test::Mojo;

use NCIPTest;

# From Koha
use Koha::Database;
use Koha::Libraries;
use Koha::Patrons;
use Koha::Items;
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

my $libraries = Koha::Libraries->search();
my $library_1 = $libraries->next();
my $library_2 = $libraries->next();
my $library_3 = $libraries->next();

my $patron_1 = $builder->build_object(
    {
        class => 'Koha::Patrons',
        value => {
            branchcode   => $library_1->id,
            categorycode => $patron_category->{categorycode},
            dateexpiry   => '2032-12-31',
            firstname    => 'Kyle',
            surname      => 'Hall',
            userid       => 'khall',
        }
    }
);

# Need to mock userenv for AddIssue
#my $module = new Test::MockModule('C4::Context');
#$module->mock('userenv', sub { { branch => $library_2->id } });

subtest 'Test AcceptItem with valid user' => sub {
    plan tests => 10;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
    #TODO: itemtype_map
    $koha_config{item_callnumber} = undef;
    $koha_config{item_itemtype} = undef;
    $koha_config{item_ccode} = undef;
    $koha_config{item_location} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/AcceptItem.xml',
        {
            patron_cardnumber => $patron_1->cardnumber,
            pickup_location   => $library_2->id,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{RequestId}->{RequestIdentifierValue}->{text},
	'KOHA-123456789',
	'AcceptItemResponse gives correct RequestIdentifierValue',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{RequestId}->{AgencyId}->{text},
	'KOHA',
	'AcceptItemResponse gives correct AgencyId',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierType}->{text},
	'Item Barcode',
	'AcceptItemResponse gives correct ItemIdentifierType',
    );

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    ok(
	$item_barcode,
	'AcceptItemResponse gives an ItemIdentifierValue'
    );

    my $item = Koha::Items->find({ barcode => $item_barcode });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    my $b = $item->biblio;
    is( $b->frameworkcode, 'FA', 'Bib has correct framework code' );
    is( $b->copyrightdate, '2001', 'Bib has correct copyright date' );
    is( $b->author, 'Guertin, Mike.', 'Bib has correct author' );
    is( $b->title, 'Precision framing', 'Bib has correct title' );

    my $bi = $item->biblioitem;
    is( $bi->publishercode, 'Taunton Press ; Publishers Group West [distributor]', 'Bib has correct publisher' );
};

subtest 'Test AcceptItem with item_branchcode set to a valid branchcode' => sub {
    plan tests => 12;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = $library_3->branchcode;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
    #TODO: itemtype_map
    $koha_config{item_callnumber} = undef;
    $koha_config{item_itemtype} = undef;
    $koha_config{item_ccode} = undef;
    $koha_config{item_location} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/AcceptItem.xml',
        {
            patron_cardnumber => $patron_1->cardnumber,
            pickup_location   => $library_2->id,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{RequestId}->{RequestIdentifierValue}->{text},
	'KOHA-123456789',
	'AcceptItemResponse gives correct RequestIdentifierValue',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{RequestId}->{AgencyId}->{text},
	'KOHA',
	'AcceptItemResponse gives correct AgencyId',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierType}->{text},
	'Item Barcode',
	'AcceptItemResponse gives correct ItemIdentifierType',
    );

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    ok(
	$item_barcode,
	'AcceptItemResponse gives an ItemIdentifierValue'
    );

    my $item = Koha::Items->find({ barcode => $item_barcode });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    my $b = $item->biblio;
    is( $b->frameworkcode, 'FA', 'Bib has correct framework code' );
    is( $b->copyrightdate, '2001', 'Bib has correct copyright date' );
    is( $b->author, 'Guertin, Mike.', 'Bib has correct author' );
    is( $b->title, 'Precision framing', 'Bib has correct title' );

    my $bi = $item->biblioitem;
    is( $bi->publishercode, 'Taunton Press ; Publishers Group West [distributor]', 'Bib has correct publisher' );

    is( $item->homebranch, $library_3->branchcode, "Item homebranch is set to the correct branchcode" );
    is( $item->holdingbranch, $library_3->branchcode, "Item holdingbranch is set to the correct branchcode" );
};

subtest 'Test AcceptItem with item_branchcode set to __PATRON__BRANCHCODE__' => sub {
    plan tests => 12;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = '__PATRON_BRANCHCODE__';
    $koha_config{always_generate_barcode} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
    #TODO: itemtype_map
    $koha_config{item_callnumber} = undef;
    $koha_config{item_itemtype} = undef;
    $koha_config{item_ccode} = undef;
    $koha_config{item_location} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/AcceptItem.xml',
        {
            patron_cardnumber => $patron_1->cardnumber,
            pickup_location   => $library_2->id,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{RequestId}->{RequestIdentifierValue}->{text},
	'KOHA-123456789',
	'AcceptItemResponse gives correct RequestIdentifierValue',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{RequestId}->{AgencyId}->{text},
	'KOHA',
	'AcceptItemResponse gives correct AgencyId',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierType}->{text},
	'Item Barcode',
	'AcceptItemResponse gives correct ItemIdentifierType',
    );

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    ok(
	$item_barcode,
	'AcceptItemResponse gives an ItemIdentifierValue'
    );

    my $item = Koha::Items->find({ barcode => $item_barcode });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    my $b = $item->biblio;
    is( $b->frameworkcode, 'FA', 'Bib has correct framework code' );
    is( $b->copyrightdate, '2001', 'Bib has correct copyright date' );
    is( $b->author, 'Guertin, Mike.', 'Bib has correct author' );
    is( $b->title, 'Precision framing', 'Bib has correct title' );

    my $bi = $item->biblioitem;
    is( $bi->publishercode, 'Taunton Press ; Publishers Group West [distributor]', 'Bib has correct publisher' );

    is( $item->homebranch, $patron_1->branchcode, "Item homebranch is set to the patron's branchcode" );
    is( $item->holdingbranch, $patron_1->branchcode, "Item holdingbranch is set to the patron's branchcode" );
};

$schema->storage->txn_rollback;
