package Koha::Plugin::Com::ByWaterSolutions::NcipServer;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use Encode;
use Mojo::JSON qw(decode_json);
use Try::Tiny;
use YAML::XS;

our $VERSION = "0.0.0";

our $metadata = {
    name            => 'NCIP server plugin',
    author          => 'ByWater Solutions',
    date_authored   => '2025-04-25',
    date_updated    => "1970-01-01",
    minimum_version => '24.05',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'NCIP server implementation',
    namespace       => 'ncip_server',
};

=head1 Koha::Plugin::Com::ByWaterSolutions::NcipServer

NCIP server plugin

=head2 Plugin methods

=head3 new

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::NcipServer->new();

Constructor method for the plugin.

=cut

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

=head3 configure

Plugin configuration method

=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'configure.tt' } );

    if ( scalar $cgi->param('op') && scalar $cgi->param('op') eq 'cud-save' ) {

        $self->store_data(
            {
                configuration => scalar $cgi->param('configuration'),
            }
        );
    }

    my $errors = $self->check_configuration;

    $template->param(
        errors        => $errors,
        configuration => $self->retrieve_data('configuration'),
    );

    $self->output_html( $template->output() );
}

=head3 api_routes

Method that returns the API routes to be merged into Koha's

=cut

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 api_routes_v3

Method that returns the API routes to be merged into Koha's

=cut

sub api_routes_v3 {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapiv3.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 api_namespace

Method that returns the namespace for the plugin API to be put on

=cut

sub api_namespace {
    my ($self) = @_;

    return 'ncip_server';
}

=head2 Internal methods

=head3 check_configuration

    my $errors = $self->check_configuration;

Returns a reference to a list of errors found in configuration.

=cut

sub check_configuration {
    my ($self) = @_;

    my @errors;

    # TODO: Add checks here, this is just an example
    push @errors, { code => 'SYSPREF_NOT_SET', syspref => 'ILLModule' }
        unless C4::Context->preference('ILLModule');

    return \@errors;
}

=head3 configuration

Accessor for the de-serialized plugin configuration

=cut

sub configuration {
    my ( $self, $params ) = @_;

    unless ( !$self->{_configuration} || $params->{force} ) {

        eval {
            $self->{_configuration} = YAML::XS::Load( Encode::encode_utf8( $self->retrieve_data('configuration') ) );
        };

        warn "[NCIP CONFIG ERROR]" . $@
            if $@;
    }

    return $self->{_configuration};
}

=head3 requires_token

    if ( $plugin->requires_token() ) { ... }

=cut

sub requires_token {
    my ($self) = @_;

    return $self->configuration->{token_required} ? 1 : 0;
}

=head3 is_token_valid

    if ( $plugin->is_token_valid($token) ) { ... }

Compares the passed token with the configured one.

=cut

sub is_token_valid {
    my ($self, $token) = @_;

    my $configured_token = $self->configuration->{auth_token} // '';

    return $configured_token eq $token;
}

1;
