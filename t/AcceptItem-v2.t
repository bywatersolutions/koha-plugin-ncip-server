#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 14;
use Test::Mojo;

use NCIPTest;

# From Koha
use C4::MarcModificationTemplates qw{ AddModificationTemplate AddModificationTemplateAction };
use Koha::Database;
use Koha::Holds;
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

subtest 'Test AcceptItem with barcode_prefix' => sub {
    plan tests => 3;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = 'ILLNCIP';
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{deny_duplicate_barcodes} = undef;
    $koha_config{request_identifier_value_as_barcode} = undef;
    $koha_config{accept_item_title_prefix} = undef;
    $koha_config{itemtype_map} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
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

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    is(
        $item_barcode,
	'ILLNCIP345678912',
	'AcceptItemResponse gives the incoming barcode with the barcode_prefix prepended',
    );

    my $item = Koha::Items->find({ barcode => $item_barcode });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    like( $item->barcode, qr/^ILLNCIP/, "Item's barcode carries the barcode_prefix" );
};

subtest 'Test AcceptItem with always_generate_barcode' => sub {
    plan tests => 5;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = 1;
    $koha_config{deny_duplicate_barcodes} = undef;
    $koha_config{request_identifier_value_as_barcode} = undef;
    $koha_config{accept_item_title_prefix} = undef;
    $koha_config{itemtype_map} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
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
            item_barcode      => 'NCIP-AGB-1',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    ok(
	$item_barcode,
	'AcceptItemResponse gives an ItemIdentifierValue'
    );

    isnt( $item_barcode, 'NCIP-AGB-1', 'Incoming barcode was ignored, a new barcode was generated' );

    is( Koha::Items->search({ barcode => 'NCIP-AGB-1' })->count, 0, 'No item was created with the incoming barcode' );

    my $item = Koha::Items->find({ barcode => $item_barcode });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    my $biblionumber = $item->biblionumber;
    like( $item->barcode, qr/^\Q$biblionumber\E\d+$/, 'Generated barcode is the biblionumber followed by a timestamp' );
};

subtest 'Test AcceptItem with deny_duplicate_barcodes' => sub {
    plan tests => 4;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{deny_duplicate_barcodes} = 1;
    $koha_config{request_identifier_value_as_barcode} = undef;
    $koha_config{accept_item_title_prefix} = undef;
    $koha_config{itemtype_map} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
    $koha_config{item_callnumber} = undef;
    $koha_config{item_itemtype} = undef;
    $koha_config{item_ccode} = undef;
    $koha_config{item_location} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $existing_item = $builder->build_sample_item( { barcode => 'NCIP-DUP-1' } );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/AcceptItem.xml',
        {
            patron_cardnumber => $patron_1->cardnumber,
            pickup_location   => $library_2->id,
            item_barcode      => 'NCIP-DUP-1',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{Problem}->{ProblemType}->{text},
	'Cannot Accept Item',
	'AcceptItemResponse gives correct problem type for an already existing barcode',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{Problem}->{ProblemDetail}->{text},
	'Item with this barcode already exists',
	'AcceptItemResponse gives correct problem detail for an already existing barcode',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{Problem}->{ProblemElement}->{text},
	'ItemIdentifierValue',
	'AcceptItemResponse gives correct problem element for an already existing barcode',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{Problem}->{ProblemValue}->{text},
	'NCIP-DUP-1',
	'AcceptItemResponse gives correct problem value for an already existing barcode',
    );
};

subtest 'Test AcceptItem with request_identifier_value_as_barcode' => sub {
    plan tests => 4;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{deny_duplicate_barcodes} = undef;
    $koha_config{request_identifier_value_as_barcode} = 1;
    $koha_config{accept_item_title_prefix} = undef;
    $koha_config{itemtype_map} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
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

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    is(
	$item_barcode,
	'KOHA-123456789',
	'RequestIdentifierValue was used as the item barcode'
    );

    my $item = Koha::Items->find({ barcode => 'KOHA-123456789' });
    is( ref($item), 'Koha::Item', 'Found item with barcode matching the RequestIdentifierValue' );

    is( $item->biblio->title, 'Precision framing', 'Bib has correct title' );
};

subtest 'Test AcceptItem with accept_item_title_prefix' => sub {
    plan tests => 4;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{deny_duplicate_barcodes} = undef;
    $koha_config{request_identifier_value_as_barcode} = undef;
    $koha_config{accept_item_title_prefix} = 'ILL: ';
    $koha_config{itemtype_map} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
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

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    ok(
	$item_barcode,
	'AcceptItemResponse gives an ItemIdentifierValue'
    );

    my $item = Koha::Items->find({ barcode => $item_barcode });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    my $b = $item->biblio;
    is( $b->title, 'ILL: Precision framing', 'Bib title is prefixed with accept_item_title_prefix' );
    is( $b->author, 'Guertin, Mike.', 'Bib author is unchanged' );
};

subtest 'Test AcceptItem with itemtype_map' => sub {
    plan tests => 4;

    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{deny_duplicate_barcodes} = undef;
    $koha_config{request_identifier_value_as_barcode} = undef;
    $koha_config{accept_item_title_prefix} = undef;
    $koha_config{itemtype_map} = { 'Book' => $itemtype->itemtype };
    $koha_config{trap_hold_on_accept_item} = undef;
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
            format            => 'Book',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    ok(
	$item_barcode,
	'AcceptItemResponse gives an ItemIdentifierValue'
    );

    my $item = Koha::Items->find({ barcode => $item_barcode });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    is( $item->itype, $itemtype->itemtype, 'Item itype is set to the itemtype mapped from the Format' );
    is( $item->biblioitem->itemtype, $itemtype->itemtype, 'Biblioitem itemtype is set to the itemtype mapped from the Format' );
};

subtest 'Test AcceptItem item default configurations' => sub {
    plan tests => 7;

    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = '9.99';
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{deny_duplicate_barcodes} = undef;
    $koha_config{request_identifier_value_as_barcode} = undef;
    $koha_config{accept_item_title_prefix} = undef;
    $koha_config{itemtype_map} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
    $koha_config{item_callnumber} = 'NCIP CALL 42';
    $koha_config{item_itemtype} = $itemtype->itemtype;
    $koha_config{item_ccode} = 'NCIP_CCODE';
    $koha_config{item_location} = 'NCIP_LOC';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/AcceptItem.xml',
        {
            patron_cardnumber     => $patron_1->cardnumber,
            pickup_location       => $library_2->id,
            omit_item_description => 1,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    ok(
	$item_barcode,
	'AcceptItemResponse gives an ItemIdentifierValue'
    );

    my $item = Koha::Items->find({ barcode => $item_barcode });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    cmp_ok( $item->replacementprice, '==', 9.99, 'Item replacement price is set from replacement_price' );
    is( $item->itemcallnumber, 'NCIP CALL 42', 'Item callnumber is set from item_callnumber when the message has no CallNumber' );
    is( $item->itype, $itemtype->itemtype, 'Item itype is set from item_itemtype' );
    is( $item->ccode, 'NCIP_CCODE', 'Item ccode is set from item_ccode' );
    is( $item->location, 'NCIP_LOC', 'Item location is set from item_location' );
};

subtest 'Test AcceptItem with trap_hold_on_accept_item disabled' => sub {
    plan tests => 6;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{deny_duplicate_barcodes} = undef;
    $koha_config{request_identifier_value_as_barcode} = undef;
    $koha_config{accept_item_title_prefix} = undef;
    $koha_config{itemtype_map} = undef;
    $koha_config{trap_hold_on_accept_item} = 0;
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

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    ok(
	$item_barcode,
	'AcceptItemResponse gives an ItemIdentifierValue'
    );

    my $item = Koha::Items->find({ barcode => $item_barcode });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    my $hold = Koha::Holds->search({ itemnumber => $item->itemnumber })->next;
    is( ref($hold), 'Koha::Hold', 'Found hold for the created item' );
    is( $hold->borrowernumber, $patron_1->borrowernumber, 'Hold belongs to the correct patron' );
    is( $hold->priority, 1, 'Hold still has priority 1' );
    is( $hold->found, undef, 'Hold was *not* trapped, found is not set' );
};

subtest 'Test AcceptItem with unknown user' => sub {
    plan tests => 4;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{deny_duplicate_barcodes} = undef;
    $koha_config{request_identifier_value_as_barcode} = undef;
    $koha_config{accept_item_title_prefix} = undef;
    $koha_config{itemtype_map} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
    $koha_config{item_callnumber} = undef;
    $koha_config{item_itemtype} = undef;
    $koha_config{item_ccode} = undef;
    $koha_config{item_location} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/AcceptItem.xml',
        {
            patron_cardnumber => 'NCIP_NO_SUCH_USER',
            pickup_location   => $library_2->id,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{Problem}->{ProblemType}->{text},
	'Unknown User',
	'AcceptItemResponse gives correct problem type for an unknown user',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{Problem}->{ProblemDetail}->{text},
	'User is not known.',
	'AcceptItemResponse gives correct problem detail for an unknown user',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{Problem}->{ProblemElement}->{text},
	'UserIdentifierValue',
	'AcceptItemResponse gives correct problem element for an unknown user',
    );

    is(
        $dom->{NCIPMessage}->{AcceptItemResponse}->{Problem}->{ProblemValue}->{text},
	'NCIP_NO_SUCH_USER',
	'AcceptItemResponse gives correct problem value for an unknown user',
    );
};

subtest 'Test AcceptItem with accept_item_marc_modification_template set' => sub {
    plan tests => 3;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{deny_duplicate_barcodes} = undef;
    $koha_config{request_identifier_value_as_barcode} = undef;
    $koha_config{accept_item_title_prefix} = undef;
    $koha_config{itemtype_map} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
    $koha_config{item_callnumber} = undef;
    $koha_config{item_itemtype} = undef;
    $koha_config{item_ccode} = undef;
    $koha_config{item_location} = undef;
    $koha_config{accept_item_marc_modification_template} = 'NCIP AcceptItem';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $template_id = AddModificationTemplate('NCIP AcceptItem');
    AddModificationTemplateAction(
        $template_id, 'copy_and_replace_field', 0,
        '245',        'a',                      '', '245', 'a',
        'Precision',  'PRECISION',              '',
        '',           '',                       '', '', '', '',
        'Copy and replace field 245$a using RegEx s/Precision/PRECISION/'
    );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/AcceptItem.xml',
        {
            patron_cardnumber => $patron_1->cardnumber,
            pickup_location   => $library_2->id,
            item_barcode      => 'NCIPMARCMOD1',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    my $item_barcode = $dom->{NCIPMessage}->{AcceptItemResponse}->{ItemId}->{ItemIdentifierValue}->{text};
    ok(
        $item_barcode,
        'AcceptItemResponse gives an ItemIdentifierValue'
    );

    my $item = Koha::Items->find({ barcode => $item_barcode });
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    is( $item->biblio->title, 'PRECISION framing', 'Title was modified by the MARC modification template' );

    # Reset accept_item_marc_modification_template
    $koha_config{accept_item_marc_modification_template} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
};

subtest 'Test AcceptItem with MediumType' => sub {
    plan tests => 4;

    $koha_config{framework} = 'FA';
    $koha_config{replacement_price} = undef;
    $koha_config{barcode_prefix} = undef;
    $koha_config{item_branchcode} = undef;
    $koha_config{always_generate_barcode} = undef;
    $koha_config{deny_duplicate_barcodes} = undef;
    $koha_config{request_identifier_value_as_barcode} = undef;
    $koha_config{accept_item_title_prefix} = undef;
    $koha_config{itemtype_map} = undef;
    $koha_config{trap_hold_on_accept_item} = undef;
    $koha_config{item_callnumber} = undef;
    $koha_config{item_itemtype} = undef;
    $koha_config{item_ccode} = undef;
    $koha_config{item_location} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    # With no itemtype configured, the MediumType value lands in 942$c
    my $ncip_message = NCIPTest::render_fixture(
        'v2/AcceptItem.xml',
        {
            patron_cardnumber => $patron_1->cardnumber,
            pickup_location   => $library_2->id,
            item_barcode      => 'NCIPMEDIUM1',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    my $item = Koha::Items->find( { barcode => 'NCIPMEDIUM1' } );
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    my @medium_itemtypes = grep { defined $_ && length $_ } map { $_->subfield('c') }
        $item->biblio->metadata->record->field('942');
    is_deeply(
        \@medium_itemtypes,
        ['Book'], "The MediumType value is in the created record's 942\$c"
    );

    # With an itemtype configured, the itemtype wins over MediumType
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
    $koha_config{itemtype_map} = { DVD => $itemtype->itemtype };
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    $ncip_message = NCIPTest::render_fixture(
        'v2/AcceptItem.xml',
        {
            patron_cardnumber => $patron_1->cardnumber,
            pickup_location   => $library_2->id,
            item_barcode      => 'NCIPMEDIUM2',
            format            => 'DVD',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    $item = Koha::Items->find( { barcode => 'NCIPMEDIUM2' } );
    is( ref($item), 'Koha::Item', 'Found item with corrosponding item barcode' );

    my @itemtypes = grep { defined $_ && length $_ } map { $_->subfield('c') }
        $item->biblio->metadata->record->field('942');
    is_deeply(
        \@itemtypes,
        [ $itemtype->itemtype ],
        "The mapped itemtype is the only 942\$c on the created record, MediumType did not override it"
    );

    # Reset itemtype_map
    $koha_config{itemtype_map} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
};

$schema->storage->txn_rollback;
