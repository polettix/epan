package App::EPAN::Base;
use v5.24;
use JSON::PP qw< decode_json >;
use Path::Tiny;
use Moo::Role;
use experimental qw< signatures >;
use namespace::clean;

requires 'parent';

has model => (is => 'lazy');

sub sources ($self) {
   my $source_target_config = sub ($app, @rest) {
      length(my $target_cfg = $app->config('target_config') // '')
         or return {};
      my $target = path($app->config('target'));
      -r (my $path = $target->child($target_cfg))
         or return {};
      return decode_json($path->slurp_raw);
   };

   return ( 
      qw< +CmdLine +Environment +Parent=40 +Default=100 >,
      [ $source_target_config, { priority => 30 } ],
   );
}

sub _build_model ($self) {
   require App::EPAN::Model;
   return App::EPAN::Model->new(
      author => $self->config('author'),
      generate_helpers => $self->config('helpers'),
      target => $self->config('target'),
   );
}

sub target ($self) { $self->config('target') }

sub refresh ($self) {
   return unless $self->config('refresh');
   if ($self->config('clean_all')) { # index only, no point in...
      $self->model->index;
   }
   else {
      $self->model->update;
   }
   return $self;
}

sub cleanup ($self) {
   my $clean_some = $self->config('clean') // 0;
   my $clean_all  = $self->config('clean_all') // 0;
   $self->model->cleanup($clean_all) if $clean_some || $clean_all;
   return $self;
}

sub housekeeping ($self) { $self->refresh->cleanup }

1;
