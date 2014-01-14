#!/usr/bin/perl -w

use strict;
use IO::File;
use File::Find;
use File::stat;

use DateTime;

use PVE::Cluster;
use PVE::APLInfo;
use PVE::SafeSyslog;
use PVE::RPCEnvironment;
use PVE::API2::Subscription;

my $debug = 0;

initlog ('pvedailycron', 'daemon');

die "please run as root\n" if $> != 0;

$ENV{'PATH'} = '/sbin:/bin:/usr/sbin:/usr/bin';

PVE::INotify::inotify_init();

my $rpcenv = PVE::RPCEnvironment->init('cli');

$rpcenv->init_request();
$rpcenv->set_language($ENV{LANG});
$rpcenv->set_user('root@pam'); 

my $nodename = PVE::INotify::nodename();

eval { PVE::API2::Subscription->update({ node => $nodename }); };
if (my $err = $@) {
   syslog ('err', "update subscription info failed: $err");
}

my $dccfg = PVE::Cluster::cfs_read_file('datacenter.cfg');
eval { PVE::APLInfo::update($dccfg->{http_proxy}); };
if (my $err = $@) {
   syslog ('err', "update appliance info failed - see /var/log/pveam.log for details");
}

sub cleanup_tasks_index {
   
    # One month before 
    my $dt = DateTime->now();
    my $one_month_before = $dt->subtract(months => 1);

    print "Delete from history task older that " . $one_month_before->datetime() 
        . " (" . $one_month_before->epoch() . ")\n" if $debug;

    my $taskdir = "/var/log/pve/tasks";
    my $filename = "$taskdir/index";
    my $history_filename = "$taskdir/index.1";

    my $fh = IO::File->new($filename, O_RDONLY);
    return if !$fh;

    my @task_list = ();
    my $count;

    while (defined(my $line = <$fh>)) {
	if ($line =~ m/^(\S+)(\s([0-9A-Za-z]{8})(\s(\S.*))?)?$/) {

            my $strFilename = $2 if $debug;
            my $hexDate = $3 if $debug;

            # on ne conserve que ce qui a moins d'un mois
	    if ($one_month_before->epoch() < hex($3)) {
                print $strFilename . '/' . localtime(hex($hexDate)) . "\n" if $debug;
                push @task_list, $line;
            }
            else {
                $count++;
            }
	}
    }
    close($fh);

    $fh = IO::File->new($history_filename, O_WRONLY|O_TRUNC);
    return if !$fh;
    foreach ( @task_list ) {
        print $fh $_;
    }
    close($fh);

    print $count . " tasks in history removed\n" if $debug;
    print @task_list . " tasks remains in history\n" if $debug;

    if ($count) {
	syslog('info', "cleanup removed $count task from history logs");
    }
}

cleanup_tasks_index();

exit (0);
