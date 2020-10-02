use Renard::Incunabula::Common::Setup;
package Qanu::API::Festival::Server;
# ABSTRACT: An IO::Async process

use base qw( IO::Async::Process );

=method configure

  method configure( %params )

=cut
method configure(%params) {
	for (qw(port)) {
		$self->{$_} = delete $params{$_} if exists $params{$_};
	}

	if( exists $self->{port} ) {
		$params{command} = [
			qw(festival --server),
			"(set! server_port @{[ $self->{port} ]})"
		],
	}

	$self->SUPER::configure(%params);
}

1;
