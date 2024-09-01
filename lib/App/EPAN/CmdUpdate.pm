package App::EPAN::CmdUpdate;
use v5.24;

use App::Easer::V2 -command => -spec => {
   aliases => [qw< update >],
   help    => 'update an EPAN repository',
   options => [ qw< clean clean_all config helpers target > ],
   description => <<'DESC',

Regenerate "index" files (much like command "index"), as well as possibly
adding ancillary files for simplified installation.

  epan update

Option `helpers` (set by default) can be used to prevent generating the
additional files, which makes this command an equivalent of command `index`.

DESC
};

use Moo;
use experimental qw< signatures >;
use namespace::clean;
with 'App::EPAN::Base';

sub commit ($self) {
   $self->set_config(refresh => 1);
   return $self;
}

sub execute ($self) {
   $self->housekeeping;
   return 0;
}

1;
