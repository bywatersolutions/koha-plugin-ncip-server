package NCIPTest;

# Test helper for the NCIP server plugin test suite.
#
# Loading this module ( after putting /kohadevbox/koha on @INC ) mocks
# 'pluginsdir' to the plugin repo root and enables plugins. This must happen
# before anything loads Koha::Plugins, which reads 'pluginsdir' in a BEGIN
# block, so 'use NCIPTest;' should come right after the 'use lib' line.

use Modern::Perl;

use Cwd qw(abs_path);
use Encode ();
use FindBin ();
use Template;
use XML::Hash;
use YAML::XS ();

use t::lib::Mocks;

our $PLUGIN_CLASS = 'Koha::Plugin::Com::ByWaterSolutions::NcipServer';

my $dom_converter = XML::Hash->new();

sub root { abs_path("$FindBin::Bin/..") }

sub import {
    t::lib::Mocks::mock_config( 'pluginsdir',     root() );
    t::lib::Mocks::mock_config( 'enable_plugins', 1 );
}

=head2 install_plugin

    my $plugin = NCIPTest::install_plugin();

Installs and enables the plugin. Call inside a transaction, everything it
writes ( plugin data, method registrations ) is rolled back with it.

=cut

sub install_plugin {
    require Koha::Plugins;
    require Koha::Plugins::Methods;
    require Koha::Plugin::Com::ByWaterSolutions::NcipServer;

    # Clear method registrations for any plugins installed on this Koha so
    # only this plugin's routes are loaded. We are inside a transaction, so
    # this is rolled back with the rest of the test.
    Koha::Plugins::Methods->search->delete;

    Koha::Plugins->new->InstallPlugins;

    my $plugin = $PLUGIN_CLASS->new;
    $plugin->enable;

    return $plugin;
}

=head2 set_config

    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

Stores the given hashref as the plugin configuration. The controller creates
a fresh plugin object per request, so changes take effect immediately.

=cut

sub set_config {
    my ( $plugin, $config ) = @_;

    $plugin->store_data( { configuration => Encode::decode_utf8( YAML::XS::Dump($config) ) } );

    return;
}

=head2 render_fixture

    my $xml = NCIPTest::render_fixture( 'v2/LookupUser.xml', { user_identifier => $cardnumber } );

Renders one of the NCIP request fixture templates from t/templates.

=cut

sub render_fixture {
    my ( $name, $vars ) = @_;

    my $tt = Template->new(
        {
            INCLUDE_PATH => root() . '/t/templates',
            INTERPOLATE  => 1,
        }
    ) || die "$Template::ERROR\n";

    my $output;
    $tt->process( $name, $vars, \$output ) || die $tt->error(), "\n";

    return $output;
}

=head2 post_ncip

    my $dom = NCIPTest::post_ncip( $t, $xml );

Posts an NCIP message to the plugin route and returns the response parsed
by XML::Hash. Makes no test assertions of its own so ported tests keep
their upstream plan counts.

=cut

sub post_ncip {
    my ( $t, $xml ) = @_;

    # No explicit content type, matching the standalone server's tests. An
    # 'application/xml' content type would make Koha 26.05 and later
    # ( Bug 37762 ) convert the body to JSON before the controller runs.
    my $tx = $t->ua->post( '/api/v1/contrib/ncip_server/ncip' => ( $xml // q{} ) );

    return $dom_converter->fromXMLStringtoHash( $tx->res->body );
}

1;
