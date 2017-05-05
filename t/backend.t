use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll'; $ENV{MOJO_MORBO_BACKEND} = 'Inotify' }

use Test::More;

use Mojo::File 'tempdir';
use Mojo::Server::Morbo;

# Prepare script
my $dir    = tempdir;
my $script = $dir->child('myapp.pl');
my $subdir = $dir->child('test', 'stuff')->make_path;
my $morbo  = Mojo::Server::Morbo->new();
$morbo->backend->watch([$subdir, $script]);
is_deeply $morbo->backend->modified_files, [], 'no files have changed';
$script->spurt(<<EOF);
use Mojolicious::Lite;

app->log->level('fatal');

get '/hello' => {text => 'Hello Morbo!'};

app->start;
EOF

# Update script without changing size
my ($size, $mtime) = (stat $script)[7, 9];
$script->spurt(<<EOF);
use Mojolicious::Lite;

app->log->level('fatal');

get '/hello' => {text => 'Hello World!'};

app->start;
EOF
is_deeply $morbo->backend->modified_files, [$script], 'file has changed';
ok((stat $script)[9] > $mtime, 'modify time has changed');
is((stat $script)[7], $size, 'still equal size');
sleep 3;

# Update script without changing mtime
($size, $mtime) = (stat $script)[7, 9];
is_deeply $morbo->backend->modified_files, [], 'no files have changed';
$script->spurt(<<EOF);
use Mojolicious::Lite;

app->log->level('fatal');

get '/hello' => {text => 'Hello!'};

app->start;
EOF
utime $mtime, $mtime, $script;
is_deeply $morbo->backend->modified_files, [$script], 'file has changed';
ok((stat $script)[9] == $mtime, 'modify time has not changed');
isnt((stat $script)[7], $size, 'size has changed');
sleep 3;

# New file(s)
is_deeply $morbo->backend->modified_files, [], 'directory has not changed';
my @new = map { $subdir->child("$_.txt") } qw/test testing/;
$_->spurt('whatever') for @new;
is_deeply $morbo->backend->modified_files, \@new, 'two files have changed';
$subdir->child('.hidden.txt')->spurt('whatever');
is_deeply $morbo->backend->modified_files, [],
  'directory has not changed again';

# Broken symlink
SKIP: {
  skip 'Symlink support required!', 4 unless eval { symlink '', ''; 1 };
  my $missing = $subdir->child('missing.txt');
  my $broken  = $subdir->child('broken.txt');
  symlink $missing, $broken;
  ok -l $broken,  'symlink created';
  ok !-f $broken, 'symlink target does not exist';
  my $warned;
  local $SIG{__WARN__} = sub { $warned++ };
  is_deeply $morbo->backend->modified_files, [], 'directory has not changed';
  ok !$warned, 'no warnings';
}

done_testing();
