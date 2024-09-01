package App::EPAN::CmdOnboard;
use v5.24;

use App::Easer::V2 -command => -spec => {
   aliases => [qw< onboard add install >],
   help    => 'onboard modules and dependencies',
   options => [ qw< clean clean_all config helpers refresh target > ],
   description => <<'DESC',

Onboard new distributions into the repository.

  epan onboard Log::Log4perl::Tiny Template::Perlish

The onboarding is performed "crudely" by calling `cpanm` and actually
installing the modules, making sure that `cpanm` is as thorough as
possible and saves all downloaded distribution files.

After the onboarding, the equivalent of command `update` is called. This
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
   $self->model->bare_onboard($self->residual_args);
   $self->housekeeping;
   return 0;
}

1;
