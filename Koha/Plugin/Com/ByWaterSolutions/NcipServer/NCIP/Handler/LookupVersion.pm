# ---------------------------------------------------------------
# Copyright © 2014 Jason J.A. Stephenson <jason@sigio.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
package Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::LookupVersion;

=head1

  Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::LookupVersion

=head1 SYNOPSIS

    Not to be called directly, Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler will pick the appropriate Handler
    object, given a message type

=head1 FUNCTIONS

=cut

use Modern::Perl;

use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Const;

our @ISA = qw(Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler);

sub handle {
    my $self   = shift;
    my $xmldoc = shift;
    if ($xmldoc) {
        my ( $from, $to ) = $self->get_agencies($xmldoc);

        return $self->render_output(
            'response.tt',
            {
                from_agency  => $to,
                to_agency    => $from,
                message_type => 'LookupVersionResponse',
                versions     => [Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Const::SUPPORTED_VERSIONS],

            }
        );
    }
}

1;
