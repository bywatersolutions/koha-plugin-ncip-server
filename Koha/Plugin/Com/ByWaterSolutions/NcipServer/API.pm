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

use Try::Tiny;
use XML::Tidy;

use Koha::Plugin::Com::ByWaterSolutions::NcipServer;

=head1 API

=head2 Class Methods

=head3 Returns TwiML for the given message

=cut

sub ncip {
    warn "Koha::Plugin::Com::ByWaterSolutions::NcipServer::API::ncip";
    my $c = shift->openapi->valid_input or return;

    my $log = Koha::Logger->get();

    return try {

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::NcipServer->new();
        my $token = $c->param('authorization_token');

        warn "TOKEN: $token";
        return $c->render(
            status => 403,
            json   => { error => 'Invalid token passed' }
        ) if $plugin->requires_token() && !$plugin->token_valid($token);

        #TODO: do actual token validation
        my $require_token = C4::Context->preference('NcipRequireToken');
        $log->debug("RETURNING. TOKEN REQUIRED BUT NOT PROVIDED") && return "It works!" if $require_token && !$token;
        $log->debug("RETURNING. TOKEN $token DOES NOT MATCH" . C4::Context->preference('NcipToken') ) && return "It works!" if $token && $token ne C4::Context->preference('NcipToken');


        my $xml;
        $xml //= $c->param('xml');
        $xml //= $c->param('XForms:Model');
        $xml //= $c->req->body;

        $log->debug("RAW XML: **$xml**");

        # Gets rid of DOCTYPE stanzas, our parser chokes on them
        $xml =~ s/<!DOCTYPE[^>[]*(\[[^]]*\])?>//g;

        # Tidy's and validates XML.
        try {
            $xml = XML::Tidy->new(xml => $xml)->tidy()->toString() if $xml;
        }
        catch {
            $log->debug("ERROR FORMATTING XML: $_");
        };
        $log->debug("FORMATTED: $xml");

        my $content;
        try {
            $content = $ncip->process_request($xml, config);
        }
        catch {
            $log->debug("ERROR PROCESSING REQUEST: $_");
        };
        $content ||= "It works!";    # No NCIP message was passed in

        my $xml_response = template 'main', {content => $content, ncip_version => $ncip->{ncip_protocol_version}};
        $xml_response = xml_tidy($xml_response);

        $log->debug("XML RESPONSE: \n$xml_response");

        return $c->render(status => 200, format => "xml", text => "<test>TEST</test>");
    }
    catch {
        $c->unhandled_exception($_);
    };
}

1;
