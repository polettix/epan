package App::EPAN::CmdInitialize;
use v5.24;

use App::Easer::V2 -command => -spec => {
   aliases => [qw< initialize init create >],
   help    => 'create a new EPAN',
   options => [qw< author helpers target >,
      {
         getopt => 'config!',
         default => 1,
         help => 'add a config.json configuraiton file',
      }
   ],
   description => <<'DESC',

Create a new repository. Complains loudly if the repository exists.

DESC
};

use Moo;
use experimental qw< signatures >;
use namespace::clean;
with 'App::EPAN::Base';

sub execute ($self) {
   $self->model->initialize($self->config('config'));
   return 0;
}

1;
