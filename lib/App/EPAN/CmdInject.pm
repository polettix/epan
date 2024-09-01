package App::EPAN::CmdInject;
use v5.24;

use App::Easer::V2 -command => -spec => {
   aliases => [qw< inject >],
   help    => 'inject distribution files',
   options => [ qw< author clean clean_all config helpers refresh target > ],
   description => <<'DESC',
Inject new distribution files into the repository.

  epan inject /path/to/distro.tar.gz /path/to/other.tar.gz

This command just injects the files provided, without regard for any
possible missing dependency.  For onboarding new distribution by name,
getting them dynamically from CPAN and getting their dependencies too,
see command `onboard`.

Option `--author|-a` is used to place the distribution in the right place
inside the repository. It defaults to `LOCAL`.

After the injection, the equivalent of command `update` is called. This
can be prevented with option `--no-refresh`. This leaves the repository
in an inconsistent state (index files do not match what's in the
repository). It might save some time if additional onboarding/injections
have to be performed.
DESC
};

use Moo;
use experimental qw< signatures >;
use namespace::clean;
with 'App::EPAN::Base';

sub execute ($self) {
   my $model = $self->model;
   $model->bare_inject($self->residual_args);
   $self->housekeeping;
   return 0;
}

1;
