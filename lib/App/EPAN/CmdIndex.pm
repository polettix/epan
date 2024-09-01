package App::EPAN::CmdIndex;
use v5.24;

use App::Easer::V2 -command => -spec => {
   aliases => [qw< index idx reindex >],
   help    => '(re-)generate index for a repository',
   options => [ qw< clean_all config target > ],
   description => <<'DESC',
Regenerate "index" files in the repository: `01mailrc.txt.gz`,
`02packages.details.txt.gz`, and `03modlist.data.gz`.

  epan index

Other ancillary files are *NOT* generated, see command `update` for a
more comprehensive approach that includes them.
DESC
};

use Moo;
use experimental qw< signatures >;
use namespace::clean;
with 'App::EPAN::Base';

sub execute ($self) {
   $self->model->index;
   $self->cleanup;
   return 0;
}

1;
