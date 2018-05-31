use strict;
use warnings;

use Test::More;
use Test::MockModule;

BEGIN {
    unshift(@INC, '.', 't');
    require 'qalter.pl';
}

my ($update, $tmsg, $test);

# poor mans main mocking
sub qalter_update {
    my ($opts, $msg) = @_;
    $test++;
    $tmsg = '' if ! defined($tmsg);
    $tmsg .= " test $test";

    is($opts->{job_id}, 123, "jobid 123 $tmsg");
    delete $opts->{job_id};

    diag "$tmsg ", explain $opts;
    is_deeply($update, $opts, "qalter update $tmsg");
};

ok(1, "Basic loading ok");


# TODO: uncomment when we know how to implement it
#@ARGV = qw(-l nodes=2:ppn=5,vmem=10gb 123 -l walltime=1:2:3);
#qalter_main();

done_testing;
