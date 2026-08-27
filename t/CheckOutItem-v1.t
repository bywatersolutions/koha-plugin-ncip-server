#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 5;
use Test::Mojo;

use NCIPTest;

# From Koha
use C4::Circulation;
use Koha::Database;
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

my $librarian = $builder->build_object(
    {
        class => 'Koha::Patrons',
        value => {
            branchcode   => $library->id,
            categorycode => $patron_category->{categorycode},
        }
    }
);
$koha_config{userenv_borrowernumber} = $librarian->id;
NCIPTest::set_config( $plugin, { koha => \%koha_config } );

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

my $item_1 = Koha::Items->search()->next();
$item_1->homebranch( $library->id );
$item_1->holdingbranch( $library->id );
$item_1->update();

subtest 'Test CheckOutItem with valid user and item' => sub {
    plan tests => 3;

    $koha_config{format_DateDue} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $ncip_message = NCIPTest::render_fixture(
        'v1/CheckOutItem.xml',
        {
            user_identifier => $patron_1->cardnumber,
            item_identifier => $item_1->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{UniqueUserId}->{UserIdentifierValue}->{text},
        $patron_1->cardnumber,
        'CheckOutItemResponse returns correct patron cardnumber'
    );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item_1->barcode,
        'CheckOutItemResponse returns correct item barcode'
    );

    is( $dom->{NCIPMessage}->{CheckOutItemResponse}->{DateDue}->{text},
        '2032-12-30T13:54:00', 'CheckOutItemResponse returns correct date due' );

};

my ( $do, $msg ) = C4::Circulation::AddReturn( $item_1->barcode, $item_1->homebranch, 1 );

subtest 'Test configuration option format_DateDue' => sub {
    plan tests => 3;

    $koha_config{format_DateDue} = 'DATE %Y-%d-%m';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $ncip_message = NCIPTest::render_fixture(
        'v1/CheckOutItem.xml',
        {
            user_identifier => $patron_1->cardnumber,
            item_identifier => $item_1->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{UniqueUserId}->{UserIdentifierValue}->{text},
        $patron_1->cardnumber,
        'format_DateDue CheckOutItemResponse returns correct patron cardnumber'
    );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item_1->barcode,
        'format_DateDue CheckOutItemResponse returns correct item barcode'
    );

    is(
	$dom->{NCIPMessage}->{CheckOutItemResponse}->{DateDue}->{text},
	'DATE 2032-30-12',
	'format_DateDue CheckOutItemResponse returns correct date due'
    );

    $koha_config{format_DateDue} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
};


subtest 'Test CheckOutItem with existing checkout' => sub {
    plan tests => 4;

    my $ncip_message = NCIPTest::render_fixture(
        'v1/CheckOutItem.xml',
        {
            user_identifier => $patron_1->cardnumber,
            item_identifier => $item_1->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorDetail}->{Value}->{text},
	undef,
        'CheckOutItemResponse returns *no* problem detail for NCIP v1'
    );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorElement}->{ProcessingErrorValue}->{text},
        $item_1->barcode,
        'CheckOutItemResponse returns correct problem barcode'
    );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorElement}->{ElementName}->{text},
        'ItemIdentifierValue',
        'CheckOutItemResponse returns correct problem element'
    );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorType}->{Value}->{text},
        'Resource Cannot Be Provided',
        'CheckOutItemResponse returns correct problem type'
    );
};

subtest 'Test CheckOutItem with invalid item' => sub {
    plan tests => 4;

    my $barcode = 'This Is A Barcode That Does Not Exist';
    my $ncip_message = NCIPTest::render_fixture(
        'v1/CheckOutItem.xml',
        {
            user_identifier => $patron_1->cardnumber,
            item_identifier => $barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorDetail}->{Value}->{text},
	undef,
        'CheckOutItemResponse returns *no* problem detail for NCIP v1'
    );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorElement}->{ProcessingErrorValue}->{text},
        $barcode,
        'CheckOutItemResponse returns correct problem barcode'
    );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorElement}->{ElementName}->{text},
        'ItemIdentifierValue',
        'CheckOutItemResponse returns correct problem element'
    );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorType}->{Value}->{text},
        'Unknown Item',
        'CheckOutItemResponse returns correct problem type'
    );
};

subtest 'Test CheckOutItem with invalid user' => sub {
    plan tests => 4;

    my $cardnumber = 'This Is An Invalid Cardnumber';

    my $ncip_message = NCIPTest::render_fixture(
        'v1/CheckOutItem.xml',
        {
            user_identifier => $cardnumber,
            item_identifier => $item_1->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorDetail}->{Value}->{text},
	undef,
        'CheckOutItemResponse returns *no* problem detail for NCIP v1'
    );

    is(
	$dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorElement}->{ProcessingErrorValue}->{text},
        $cardnumber,
        'CheckOutItemResponse returns correct problem barcode'
    );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorElement}->{ElementName}->{text},
        'UserIdentifierValue',
        'CheckOutItemResponse returns correct problem element'
    );

    is(
        $dom->{NCIPMessage}->{CheckOutItemResponse}->{Problem}->{ProcessingError}->{ProcessingErrorType}->{Value}->{text},
        'Unknown User',
        'CheckOutItemResponse returns correct problem type'
    );
};

$schema->storage->txn_rollback;
