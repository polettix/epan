package App::EPAN::CmdEject;
use v5.24;

use App::Easer::V2 -command => -spec => {
   aliases => [qw< eject remove >],
   help    => 'remove distributions',
   options => [ qw< clean clean_all config helpers refresh target > ],
   description => <<'DESC',
Remove one or more distribution files from the repository.

  epan eject FOOBAR/Some-Dist-0.001.tar.gz "$other_distro"

Names of distribution files inside the repository are saved in file
`distlist.txt`, inside the repository base directory, if present. Otherwise,
they can be specified as `AUTHOR/DistroFile-....tar.gz`.

Distribution that are not present are ignored (with a log message).
DESC
};

use Moo;
use experimental qw< signatures >;
use namespace::clean;
with 'App::EPAN::Base';

sub execute ($self) {
   $self->model->bare_eject($self->residual_args);
   $self->housekeeping;
   return 0;
}

1;
