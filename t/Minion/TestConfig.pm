package Minion::TestConfig;

use strict;
use warnings;

use Carp qw(confess);


sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, $values, @err) = @_;

    confess() if (@err);
    confess() if (!defined($values));
    confess() if (ref($values) ne 'HASH');
    confess() if (grep { ref($_) ne '' } values(%$values));

    $self->{__PACKAGE__()}->{_values} = { %$values };

    return $self;
}


sub __tokenize_line
{
    my ($line) = @_;
    my (@tokens, $c, $ctx, $esc, $cur);

    $cur = '';
    $ctx = '';
    $esc = 0;

    foreach $c (split(//, $line)) {
	if ($esc) {
	    $cur .= $c;
	    $esc = 0;
	    next;
	}

	if ($c eq '\\') {
	    $esc = 1;
	    next;
	}

	if (($c eq "'") || ($c eq '"')) {
	    if ($ctx eq '') {
		$ctx = $c;
		next;
	    } elsif ($ctx eq $c) {
		$ctx = '';
		next;
	    }
	}

	if (($c =~ /\s/) && ($ctx eq '')) {
	    if ($cur ne '') {
		push(@tokens, $cur);
		$cur = '';
	    }
	    next;
	}

	if (($c eq '#') && ($ctx eq '')) {
	    if ($cur ne '') {
		push(@tokens, $cur);
		$cur = '';
	    }
	    last;
	}

	$cur .= $c;
    }

    if ($esc || ($ctx ne '')) {
	return undef;
    }

    if ($cur ne '') {
	push(@tokens, $cur);
    }

    return \@tokens;
}

sub load
{
    my ($class, $path, $ehandler, @err) = @_;
    my (%values, $fh, $ln, $line, $tokens, $token, $key, $value);

    confess() if (@err);
    confess() if (!defined($path));
    confess() if (ref($path) ne '');

    if (defined($ehandler)) {
	confess() if (ref($ehandler) ne 'CODE');
    } else {
	$ehandler = sub {
	    my ($path, $ln, $obj) = @_;

	    if ($ln > 0) {
		printf(STDERR "%s:%d: syntax error: '%s'\n", $path, $ln, $obj);
	    } else {
		printf(STDERR "%s: cannot open file: %s\n", $path, $obj);
	    }
	};
    }

    if (!open($fh, '<', $path)) {
	$ehandler->($path, 0, $!);
	return undef;
    }

    $ln = 0;

    while (defined($line = <$fh>)) {
	$ln += 1;

	chomp($line);

	$tokens = __tokenize_line($line);

	if (!defined($tokens)) {
	    close($fh);
	    $ehandler->($path, $ln, $line);
	    return undef;
	}

	if (scalar(@$tokens) == 0) {
	    next;
	}

	if ((scalar(@$tokens) < 2) || (scalar(@$tokens) > 3)) {
	    close($fh);
	    $ehandler->($path, $ln, $line);
	    return undef;
	}

	$key = $tokens->[0];

	if (scalar(@$tokens) == 3) {
	    $value = $tokens->[2];
	} else {
	    $value = undef;
	}

	$values{$key} = $value;
    }

    close($fh);

    return $class->new(\%values);
}


sub has
{
    my ($self, $name, @err) = @_;

    confess() if (@err);
    confess() if (!defined($name));
    confess() if (ref($name) ne '');
    
    return exists($self->{__PACKAGE__()}->{_values});
}

sub get
{
    my ($self, $name, @err) = @_;

    confess() if (@err);
    confess() if (!defined($name));
    confess() if (ref($name) ne '');

    return $self->{__PACKAGE__()}->{_values}->{$name};
}


sub from_path
{
    my ($class, $path, @names) = @_;
    my ($config, $name, %params);

    confess() if (!defined($path));
    confess() if (ref($path) ne '');
    confess() if (scalar(@names) == 0);
    confess() if (grep { ref($_) ne '' } @names);

    $config = __PACKAGE__()->load($path);

    if (!defined($config)) {
	return "cannot load config from '$path'";
    }

    foreach $name (@names) {
	if (!$config->has($name)) {
	    return "cannot find parameter '$name' in '$path'";
	}

	$params{$name} = $config->get($name);
    }

    return \%params;
}


1;
__END__
