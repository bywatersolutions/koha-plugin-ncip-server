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

use Mojo::JSON qw(decode_json);
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

        # Koha 26.05 and later ( Bug 37762 ) converts request bodies sent with
        # an 'application/xml' content type to JSON before the controller
        # runs, which destroys the NCIP message. Recover the original from
        # the buffered PSGI input if the server kept it, otherwise rebuild
        # workable XML from the JSON conversion
        my $content_type = $c->req->headers->content_type // q{};
        if ( $xml =~ /^\s*\{/ && $content_type =~ m{application/xml} ) {
            if ( my $raw = _recover_raw_body($c) ) {
                $xml = $raw;
                $logger->info("NCIP: recovered the original request body from the buffered PSGI input");
            }
            elsif ( my $rebuilt = _rebuild_xml_from_json($xml) ) {
                $xml = $rebuilt;
                $logger->info("NCIP: rebuilt the request from Koha's JSON conversion, NCIP version 2 assumed");
            }
            else {
                $logger->warn( "NCIP: the request body was converted to JSON by Koha's REST API ( Bug 37762 ) "
                        . "and could not be recovered" );
            }
        }

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

        # Set the content type by hand, with the charset included. A bare
        # 'application/xml' makes Koha 26.05 and later ( Bug 37762 ) treat the
        # response body as JSON to be converted to XML, which fails on our
        # already-XML body. This also matches the standalone server's
        # default_mime_type.
        $c->res->headers->content_type('application/xml; charset=utf-8');

        return $c->render( status => 200, text => $response );
    }
    catch {
        $c->unhandled_exception($_);
    };
}

=head2 Internal methods

=head3 _recover_raw_body

Returns the original request body from the buffered PSGI input, or undef.

=cut

sub _recover_raw_body {
    my ($c) = @_;

    # Under PSGI servers that buffer the request body ( Koha's Starman
    # deployment does ), the original bytes are still readable from the
    # PSGI environment even after Koha replaced the Mojo request body
    my $env = $c->req->can('env') ? $c->req->env : undef;
    return unless ref($env) eq 'HASH';
    return unless $env->{'psgix.input.buffered'};

    my $input = $env->{'psgi.input'} or return;

    my $raw;
    eval {
        my $position = tell($input);
        if ( seek( $input, 0, 0 ) ) {
            local $/;
            $raw = <$input>;
            seek( $input, $position, 0 ) if defined $position && $position >= 0;
        }
    };

    return unless defined $raw && length $raw;
    return $raw;
}

=head3 _rebuild_xml_from_json

Rebuilds an NCIP XML message from Koha's JSON conversion of it, or undef.

=cut

sub _rebuild_xml_from_json {
    my ($json) = @_;

    my $data = eval { decode_json($json) };
    return unless ref($data) eq 'HASH' && ref( $data->{NCIPMessage} ) eq 'HASH';

    # The version attribute and element order were lost in the conversion,
    # so NCIP version 2 is assumed. The handlers' XPath extraction does not
    # depend on element order.
    return
          qq{<NCIPMessage xmlns="http://www.niso.org/2008/ncip" }
        . qq{version="http://www.niso.org/schemas/ncip/v2_02/ncip_v2_02.xsd">}
        . _hash_to_xml( $data->{NCIPMessage} )
        . qq{</NCIPMessage>};
}

=head3 _hash_to_xml

Serializes a nested hash from Koha's XML to JSON conversion back into XML.

=cut

sub _hash_to_xml {
    my ($value) = @_;

    if ( ref($value) eq 'HASH' ) {
        my $xml = q{};
        for my $key ( sort keys %$value ) {
            my $child = $value->{$key};
            if ( ref($child) eq 'ARRAY' ) {
                $xml .= '<' . $key . '>' . _hash_to_xml($_) . '</' . $key . '>' for @$child;
            }
            else {
                $xml .= '<' . $key . '>' . _hash_to_xml($child) . '</' . $key . '>';
            }
        }
        return $xml;
    }

    return _xml_escape( $value // q{} );
}

=head3 _xml_escape

=cut

sub _xml_escape {
    my ($text) = @_;

    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;

    return $text;
}

1;
