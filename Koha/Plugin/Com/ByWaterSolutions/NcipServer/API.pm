package Koha::Plugin::Com::ByWaterSolutions::NcipServer::API;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use Template;
use Try::Tiny;
use XML::LibXML;

use Koha::Logger;

use Koha::Plugin::Com::ByWaterSolutions::NcipServer;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP;

=head1 API

=head2 Class Methods

=head3 ncip

Processes an incoming NCIP XML message and returns the NCIP XML response

=cut

sub ncip {
    my $c = shift->openapi->valid_input or return;

    my $logger = Koha::Logger->get( { category => 'plugin.ncipserver' } );

    return try {
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::NcipServer->new();

        my $config = $plugin->configuration;
        return $c->render(
            status => 500,
            json   => { error => 'NCIP server plugin configuration is invalid' }
        ) unless defined $config;

        if ( $plugin->requires_token ) {
            my $token = $c->param('authorization_token');

            return $c->render(
                status => 403,
                json   => { error => 'Invalid or missing authorization token' }
            ) unless defined $token && $plugin->is_token_valid($token);
        }

        # Same precedence as the standalone server: form or query param
        # 'xml', then 'XForms:Model', then the raw request body
        my $xml = $c->param('xml') // $c->param('XForms:Model') // $c->req->body // q{};

        # Gets rid of DOCTYPE stanzas, our parser chokes on them
        $xml =~ s/<!DOCTYPE[^>[]*(\[[^]]*\])?>//g;

        my $ncip = Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP->new();

        my $content;
        try {
            $content = $ncip->process_request( $xml, $config );
        }
        catch {
            $logger->warn("NCIP: error processing request: $_");
        };
        $content ||= "It works!";    # No (valid) NCIP message was passed in

        my $template = Template->new( { INCLUDE_PATH => $ncip->templates_dir, ENCODING => 'UTF-8' } );
        my $response = q{};
        $template->process(
            'main.tt',
            {
                content      => $content,
                ncip_version => $ncip->{ncip_protocol_version} // 2,
            },
            \$response
        ) or die $template->error();

        # Pretty-print and check well-formedness, replaces the standalone
        # server's XML::Tidy pass
        try {
            $response = XML::LibXML->load_xml( string => $response )->toString(1);
        }
        catch {
            $logger->warn("NCIP: response is not well-formed XML: $_");
        };

        return $c->render( status => 200, format => 'xml', text => $response );
    }
    catch {
        $c->unhandled_exception($_);
    };
}

1;
