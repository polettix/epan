package App::EPAN::CmdClean;
use v5.24;

use App::Easer::V2 -command => -spec => {
   aliases => [qw< clean cleanup clean-local cleanup-local >],
   help    => 'cleanup "local" sub-dir of repo',
   options => [ qw< config target >,
      {
         getopt   => 'all|a!',
         help     => 'cleanup the "local" directory and other ancillary files',
         default  => 0,
         transmit => 1,
      },

   ],
   description => <<'DESC',
Cleanup the repository directory, removing the `local` directory where
modules are installed during the gathering process.

  epan clean
DESC
};

use Moo;
use experimental qw< signatures >;
use namespace::clean;
with 'App::EPAN::Base';

# ensure something is cleaned up!
sub commit ($self) {
   $self->set_config(clean => 1);
   $self->set_config(clean_all => $self->config('all'));
}

sub execute ($self) {
   $self->cleanup;
   return 0;
}

1;
