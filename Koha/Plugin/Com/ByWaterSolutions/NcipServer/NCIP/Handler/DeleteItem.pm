package Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::DeleteItem;

=head1

  Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::DeleteItem

=head1 SYNOPSIS

    Not to be called directly, Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler will pick the appropriate Handler 
    object, given a message type

=head1 FUNCTIONS

=cut

use Modern::Perl;

use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler;

our @ISA = qw(Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler);

sub handle {
    my $self   = shift;
    my $xmldoc = shift;
    if ($xmldoc) {
        my $root   = $xmldoc->documentElement();

        my $config = $self->{config}->{koha};

        my $itemid = $self->find_nodes( '//ItemIdentifierValue', $root );

        # check in the item
        my $branch = undef;    # where the hell do we get this from???
        my ( $from, $to ) = $self->get_agencies($xmldoc);

        my $deletion = $self->ils->delete_item(
            {
                barcode => $itemid,
                branch  => $branch,
                config  => $config,
            }
        );

        if ( $deletion->{success} ) {
            return $self->render_output(
                'response.tt',
                {
                    message_type => 'DeleteItemResponse',
                    barcode      => $itemid,
                    from_agency  => $to,
                    to_agency    => $from,
                    elements     => $self->get_user_elements($xmldoc),
                    deletion     => $deletion,
                }
            );
        }
        else {
            return $self->render_output(
                'problem.tt',
                {
                    message_type => 'DeleteItemResponse',
                    problems     => $deletion->{problems},
                    from_agency  => $to,
                    to_agency    => $from,
                }
            );
        }
    }
}

1;
