#!/usr/bin/env perl

use Test::Most tests => 1;

use Modern::Perl;

use IO::Async::Loop;
use IO::Async::Process;
use IO::Async::Stream;

use Net::EmptyPort qw(empty_port);

use constant DEBUG => 1;
use constant KEY     => "ft_StUfF_key";
use constant KEYLEN  => length KEY;

use Carp::Always;
subtest "Run festival" => sub {
	my $loop = IO::Async::Loop->new;

	my $port = empty_port();

	my @commands = (
		#qq|(SayText "Hey")|,
		qq|(voice.list)|,
		#qq|(set! utt1 (Utterance Text "Hello world"))|,
		qq|(tts_textall "hey" nil)|,
		qq|(set! utt1 (Utterance Text "Mr. James Brown Jr. attended flight No AA4101 to Boston on Friday 02/13/2014."))|,
		qq|(utt.synth utt1)|,
		qq|(utt.relation_tree utt1 'SylStructure)|,
		qq|(utt.relation_tree utt1 'Token)|,
		qq|(tts_textall "hey" nil)|,
		qq|(utt.relation_tree utt1 'Token)|,
		qq|(utt.relation_tree utt1 'SylStructure)|,
		qq|(exit)|,
	);

	my $server_ready = $loop->new_future;
	my $client_done = $loop->new_future;

	$loop->add(
		my $process = IO::Async::Process->new(
			command => [ qw(festival --server), "(set! server_port $port)" ],
			on_finish => sub {
				$loop->stop;
			},
			stdout => {
				on_read => sub {
					my ( $stream, $buffref ) = @_;
					if( $$buffref =~ /Festival server started on port/ ) {
						$server_ready->done;
					}

					while( $$buffref =~ s/^(.*)\n//s ) {
						print "Server message: '$1'\n";
					}

					return 1;
				},
			},
		)
	);

	my $cmd_idx = 0;

	my $file_stuff_key = "ft_StUfF_key"; # defined in speech tools

	my $current_tag;
	my $current_data;
	my $tag_data;
	$loop->add(
		my $stream = IO::Async::Stream->new(
			on_read => sub {
				my ( $self, $buffref, $eof ) = @_;

				my @tags = qw(WV LP OK ER);
			    $self->{inbuf} .= $$buffref;

			    my $count = 0;
			 CHUNK:
			    while (length($self->{inbuf}) > 0) {
				# In the middle of a tag?
				if ($self->{intag}) {
				    # Look for the stuff key
				    if ((my $i = index($self->{inbuf}, KEY)) != $[-1) {
					if (substr($self->{inbuf}, $i+KEYLEN, 1) eq 'X') {
					    # If there's an X at the end, it's literal
					    substr($self->{inbuf}, $i+KEYLEN, 1) = "";
					} else {
					    # Otherwise, we've got a complete waveform/expr/whatever
					    push @{$self->{inq}{$self->{intag}}},
						substr($self->{inbuf}, 0, $i);
					    print "queued $i bytes of $self->{intag}\n" if DEBUG;
					    substr($self->{inbuf}, 0, $i+KEYLEN) = "";
					    $self->{intag} = "";
					    $count += $i;
					}
				    } else {
					# Maybe we got *part* of the stuff key at the end of
					# this block.  Stranger things have happened.
					my $leftover = "";
				    PARTIAL:
					for my $sub (1..KEYLEN-1) {
					    my $foo = \substr($self->{inbuf}, -$sub);
					    my $bar = substr(KEY, 0, $sub);
					    if ($$foo eq $bar) {
						$$foo = "";
						$leftover = $bar;
						last PARTIAL;
					    }
					}

					# In any case we don't have any more data
					push @{$self->{inq}{$self->{intag}}}, $self->{inbuf};
					print "queued ", length($self->{inbuf}), " bytes of $self->{intag}\n"
					    if DEBUG;
					$count += length($self->{inbuf});
					$self->{inbuf} = $leftover;

					# But don't keep looping if we left some stuff in there!
					last CHUNK if $leftover;
				    }
				} else {
				    if ($self->{inbuf} =~ s/^(WV|LP|ER|OK)\n//) {
					print "got tag $1\n" if DEBUG;
					$count += length($1);
					# We got a tag, so a new type of data is coming
					if ($1 eq 'OK') {
					    push @{$self->{inq}{OK}}, time;
					} elsif ($1 eq 'ER') {
					    push @{$self->{inq}{ER}}, time;
					} else {
					    $self->{intag} = $1;
					}
				    } else {
					# Should not actually be fatal, it's always possible
					# we just got the middle of a tag.
					last CHUNK;
				    }
				}
			    }

				#DATA:
				#while ( length $$buffref && $$buffref =~ s/^(.*)\n//s ) {
					#my $data = $1;
					#TAG:
					#for my $tag (@tags) {
						#if( $data =~ s/^\Q$tag\E//s ) {
							#say "We got a tag $tag";
							#$current_tag = $tag;
							#$current_data = { tag => $current_tag, data => '' };
							#push @$tag_data, $current_data;
							#next DATA;
						#}
					#}

					#my $keep;
					#my $length;

					#if( $data =~ /^(.+?)$file_stuff_key/s ) {
						#$keep = $1;
						#$length = length($keep) + length($file_stuff_key);
						#undef $current_tag;
					#} else {
						#$keep = $data;
						#$length = length $data;
					#}

					#substr $data, 0, $length, '';
					#$current_data->{data} .= $keep;
				#}
				#use DDP; p $self->{inq};

				#say "Left: |$$buffref|", length($$buffref);
				#say "Done with this read";
				#sleep 1;
				$$buffref = '';

				if( $cmd_idx >= @commands ) {
					$client_done->done;
				} else {
					$self->write( $commands[$cmd_idx++] );# unless $self->{inbuf}
				}

				return $count;
			},
		)
	);

	$server_ready->on_ready(sub {
		$stream->connect(
			host => 'localhost',
			service => $port,
			on_connected => sub {
				$stream->write( $commands[$cmd_idx++] );
			},
			on_resolve_error => sub { die "Cannot resolve - $_[0]\n" },
			on_connect_error => sub { die "Cannot connect\n" },
		);
	});

	$client_done->on_ready(sub {
		local $Data::Dumper::Useqq = 1;
		use Data::Dumper; print Dumper $stream->{inq};
		$stream->close;
		use POSIX qw(SIGQUIT);
		$process->kill( SIGQUIT );
		$loop->stop;
	});


	$loop->run;

	pass;
};

done_testing;
