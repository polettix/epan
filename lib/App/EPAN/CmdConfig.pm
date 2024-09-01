package App::EPAN::CmdConfig;
use v5.24;
use experimental qw< signatures >;
use JSON::PP ();
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;

use App::Easer::V2 -command => -spec => {
   aliases => [qw< config >],
   help    => 'print configuration as JSON',
   options => [ '+parent' ],
   description => <<'DESC',
Print configuration as a JSON file.
DESC
};

sub execute ($self) {
   say JSON::PP->new->ascii->canonical->pretty->encode($self->config_hash);
   return 0;
}

1;
