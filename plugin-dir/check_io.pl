#!/usr/bin/perl -w
# nagios: -epn

#######################################################
#                                                     #
#  Name:    check_io                                  #
#                                                     #
#  Version: 0.1                                       #
#  Created: 2012-12-13                                #
#  License: GPL - http://www.gnu.org/licenses         #
#  Copyright: (c)2012 ovido gmbh, http://www.ovido.at #
#  Author:  Rene Koch <r.koch@ovido.at>               #
#  Credits: s IT Solutions AT Spardat GmbH            #
#  URL: https://labs.ovido.at/monitoring              #
#                                                     #
#######################################################

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use Getopt::Long;
use List::Util qw( min max sum );

# Configuration
my $tmp_errors = "/var/tmp/check_io_";

# create performance data
# 0 ... disabled
# 1 ... enabled
my $perfdata	= 1;

# Variables
my $prog	= "check_io";
my $version	= "0.1";
my $projecturl  = "https://labs.ovido.at/monitoring/wiki/check_io";

my $o_verbose	= undef;	# verbosity
my $o_help	= undef;	# help
my $o_version	= undef;	# version
my $o_runs	= 5;		# iostat runs
my $o_interval	= 1;		# iostat interval
my @o_exclude	= ();		# exclude disks
my $o_errors	= undef;	# error detection
my $o_max	= undef;	# get max values
my $o_average	= undef;	# get average values
my $o_warn	= undef;	# warning
my $o_crit	= undef;	# critical
my @warn	= ();
my @crit	= ();

my %status	= ( ok => "OK", warning => "WARNING", critical => "CRITICAL", unknown => "UNKNOWN");
my %ERRORS	= ( "OK" => 0, "WARNING" => 1, "CRITICAL" => 2, "UNKNOWN" => 3);

my $statuscode	= "unknown";
my $statustext	= "";
my $perfstats	= "|";
my %errors;

#***************************************************#
#  Function: parse_options                          #
#---------------------------------------------------#
#  parse command line parameters                    #
#                                                   #
#***************************************************#
sub parse_options(){
  Getopt::Long::Configure ("bundling");
  GetOptions(
	'v+'	=> \$o_verbose,		'verbose+'	=> \$o_verbose,
	'h'	=> \$o_help,		'help'		=> \$o_help,
	'V'	=> \$o_version,		'version'	=> \$o_version,
	'r:i'	=> \$o_runs,		'runs:i'	=> \$o_runs,
	'i:i'	=> \$o_interval,	'interval:i'	=> \$o_interval,
	'e:s'	=> \@o_exclude,		'exclude:s'	=> \@o_exclude,
	'E'	=> \$o_errors,		'errors'	=> \$o_errors,
	'm'	=> \$o_max,		'max'		=> \$o_max,
	'a'	=> \$o_average,		'average'	=> \$o_average,
	'w:s'	=> \$o_warn,		'warning:s'	=> \$o_warn,
	'c:s'	=> \$o_crit,		'critical:s'	=> \$o_crit
  );

  # process options
  print_help()		if defined $o_help;
  print_version()	if defined $o_version;

  # can't use max and average
  if (defined $o_max && defined $o_average){
    print "Can't use max and average at the same time!\n";
    print_usage();
    exit $ERRORS{$status{'unknown'}};
  }

  if ((! defined $o_warn) || (! defined $o_crit)){
    print "Warning and critical values are required!\n";
    print_usage();
    exit $ERRORS{$status{'unknown'}};
  }

  # check warning and critical
  if ($o_warn !~ /^(\d+)(\.?\d+)*,{1}(\d+)(\.?\d+)*,(\d+)(\.?\d+)*$/){
    print "Please give proper warning values!\n";
    print_usage();
    exit $ERRORS{$status{'unknown'}};
  }else{
    @warn = split /,/, $o_warn;
  }

  if ($o_crit !~ /^(\d+)(\.?\d+)*,{1}(\d+)(\.?\d+)*,(\d+)(\.?\d+)*$/){
    print "Please give proper critical values!\n";
    print_usage();
    exit $ERRORS{$status{'unknown'}};
  }else{
    @crit = split /,/, $o_crit;
  }

  # verbose handling
  $o_verbose = 0 if ! defined $o_verbose;

}


#***************************************************#
#  Function: print_usage                            #
#---------------------------------------------------#
#  print usage information                          #
#                                                   #
#***************************************************#
sub print_usage(){
  print "Usage: $0 [-v] [-r <runs>] [-i <interval>] [-e <exclude>] [-E] [-m|-a] \n";
  print "        -w <tps,svctm,wait> -c <tps,svctm,wait>\n";
}


#***************************************************#
#  Function: print_help                             #
#---------------------------------------------------#
#  print help text                                  #
#                                                   #
#***************************************************#
sub print_help(){
  print "\nLinux and Solaris I/O checks for Icinga/Nagios version $version\n";
  print "GPL license, (c)2012 - Rene Koch <r.koch\@ovido.at>\n\n";
  print_usage();
  print <<EOT;

Options:
 -h, --help
    Print detailed help screen
 -V, --version
    Print version information
 -r, --runs=INTEGER
    iostat count (default: $o_runs)
 -i, --interval=INTEGER
    iostat interval (default: $o_interval)
 -e, --exclude=REGEX
    Regex to exclude disks from beeing checked
 -E, --errors
    Check disk errors on Solaris
 -m, --max
    Use max. values of runs for tps, svctm and iowait (default)
 -a, --average
    Use average values of runs for tps, svctm and iowait
 -w, --warning=<tpd,svctm,wait>
    Value to result in warning status
    tps: transfers per second
    svctm: avg service time for I/O requests issued to the device
    wait: CPU I/O waiting for outstanding I/O requests
 -c, --critical=<tpd,svctm,wait>
    Value to result in critical status
    tps: transfers per second
    svctm: avg service time for I/O requests issued to the device
    wait: CPU I/O waiting for outstanding I/O requests
 -v, --verbose
    Show details for command-line debugging
    (Icinga/Nagios may truncate output)

Send email to r.koch\@ovido.at if you have questions regarding use
of this software. To submit patches of suggest improvements, send
email to r.koch\@ovido.at
EOT

exit $ERRORS{$status{'unknown'}};
}



#***************************************************#
#  Function: print_version                          #
#---------------------------------------------------#
#  Display version of plugin and exit.              #
#                                                   #
#***************************************************#

sub print_version{
  print "$prog $version\n";
  exit $ERRORS{$status{'unknown'}};
}


#***************************************************#
#  Function: main                                   #
#---------------------------------------------------#
#  The main program starts here.                    #
#                                                   #
#***************************************************#

# parse command line options
parse_options();

# get operating system
my $kernel_name = `uname -s`;
my $kernel_release = `uname -r | cut -d- -f1`;
chomp $kernel_name;
chomp $kernel_release;

my $cmd = undef;

if ($kernel_name eq "Linux"){

  # get list of devices
  my $devices = "";
  my @tmp = `iostat -d`;
  for (my $i=0;$i<=$#tmp;$i++){
    next if $tmp[$i] =~ /^$/;
    next if $tmp[$i] =~ /^Linux/;
    next if $tmp[$i] =~ /^Device:/;
    chomp $tmp[$i];
    my @dev = split / /, $tmp[$i];

    # match devs with exclude list
    my $match = 0;
    for (my $x=0;$x<=$#o_exclude;$x++){
      $match = 1 if $dev[0] =~ /$o_exclude[$x]/;
    }

    # exclude cd drives
    if (-e "/dev/cdrom"){
      my $cdrom = `ls -l /dev/cdrom | tr -s ' ' ' ' | cut -d' ' -f11`;
      chomp $cdrom;
      next if $dev[0] eq $cdrom;
    }

    # RHEL 5: can't use -x and -p at the same time
    if ($kernel_release =~ /2.6.18/){
      $devices .= " " . $dev[0] if $match != 1;
    }else{
      $devices .= " -p " . $dev[0] if $match != 1;
    }

  }

  $cmd = "iostat -kx" . $devices . " " . $o_interval . " " . $o_runs;
#    print "CMD: $cmd \n";

}elsif ($kernel_name eq "SunOS"){

    my $devices = "";
    my @tmp = `iostat -xn`;
    for (my $i=0;$i<=$#tmp;$i++){
      next if $tmp[$i] =~ /^$/;
      next if $tmp[$i] =~ /^(\s+)extended(\s)device(\s)statistics/;
      next if $tmp[$i] =~ /^(\s+)r\/s(\s+)w\/s(\s+)kr\/s/;
      chomp $tmp[$i];
      $tmp[$i] =~ s/\s+/ /g;
      my @dev = split / /, $tmp[$i];

      # match devs with exclude list
      my $match = 0;
      for (my $x=0;$x<=$#o_exclude;$x++){
	$match = 1 if $dev[11] =~ /$o_exclude[$x]/;
      }

      # exclude cd drives
      if (-e "/dev/sr0"){
	my $cdrom = `ls -l /dev/sr0 | tr -s ' ' ' ' | cut -d' ' -f11 | cut -d/ -f2`;
        chop $cdrom;
        chop $cdrom;
        chop $cdrom;
	next if $dev[11] eq $cdrom;
      }

      # skip automount devices
      next if $dev[11] =~ /vold\(pid\d+\)/;

      $devices .= " " . $dev[11] if $match != 1;

      # handle temp files for disk
      if (defined $o_errors){
        if (! -e $tmp_errors . "_" . $dev[11]){
          if (! open (TMPERRORS, ">$tmp_errors" . "_" . $dev[11]) ){
	    print "File $tmp_errors isn't writeable!\n";
	    exit $ERRORS{$status{'unknown'}};
          }
          # fill file with 0 values
          my @a = ("soft","hard","transport","media","drive","nodev","recoverable","illegal");
	  foreach (@a){
	    print TMPERRORS $_ . " 0\n";
	    $errors{$dev[11]}{$_} = 0;
	  }
          close (TMPERRORS);
        }else{
          if (! -w $tmp_errors . "_" . $dev[11]){
	    print "File $tmp_errors isn't writeable!\n";
	    exit $ERRORS{$status{'unknown'}};
          }
          # read values
          open TMPERRORS, $tmp_errors . "_" . $dev[11];
          while (<TMPERRORS>){
	    my @tmp = split / /, $_;
	    $errors{$dev[11]}{$tmp[0]} = $tmp[1];
          }
          close (TMPERRORS);
        }
      }

    }
    if (defined $o_errors){
      $cmd = "iostat -Excn" . $devices . " " . $o_interval . " " . $o_runs;
    }else{
      $cmd = "iostat -xcn" . $devices . " " . $o_interval . " " . $o_runs;
    }
#    print "CMD: $cmd \n";

}else{
  exit_plugin ("unknown", "Operating system $kernel_name isn't supported, yet.");
}

my %iostat;
my $x=0;
my $hdd = undef;

# get statistics from iostat
my @result = `$cmd`;
for (my $i=0;$i<=$#result;$i++){

  $result[$i] =~ s/\s+/ /g;

    # Fedora / RHEL:
    # Linux 3.4.11-1.fc16.x86_64 (pc-ovido02.lan.ovido.at) 	12/11/2012 	_x86_64_	(4 CPU)
    #
    # avg-cpu:  %user   %nice %system %iowait  %steal   %idle
    #            6.15    0.00    2.94    1.93    0.00   88.98
    #
    # Device:         rrqm/s   wrqm/s     r/s     w/s    rkB/s    wkB/s avgrq-sz avgqu-sz   await r_await w_await  svctm  %util
    # sda               0.40    10.24    3.41   13.54    70.65   103.22    20.52     0.26   15.27   13.18   15.80   4.41   7.47

    # Solaris:
    #     cpu
    # us sy wt id
    #  1  1  0 98
    #                    extended device statistics              
    #    r/s    w/s   kr/s   kw/s wait actv wsvc_t asvc_t  %w  %b device
    #    0.3    1.6   15.8   12.0  0.0  0.0    5.0    3.2   0   0 c0d0

#print "LINE: $result[$i]\n";

    # get disk statistics on Linux
    if ( $result[$i] =~ /^(\w+)(-*)(\d*)(\s)((\d+)\.(\d+)(\s){1}){5}(\d+)\.(\d+)/ ){

      my @tmp = split / /, $result[$i];
      $iostat{$tmp[0]}{'rs'}[$x-1] = $tmp[3];
      $iostat{$tmp[0]}{'ws'}[$x-1] = $tmp[4];
      $iostat{$tmp[0]}{'rkBs'}[$x-1] = $tmp[5];
      $iostat{$tmp[0]}{'wkBs'}[$x-1] = $tmp[6];
      $iostat{$tmp[0]}{'wait'}[$x-1] = $tmp[9];
      if ($kernel_release =~ /2.6.18/){
        $iostat{$tmp[0]}{'svctm'}[$x-1] = $tmp[10];
      }else{
        $iostat{$tmp[0]}{'svctm'}[$x-1] = $tmp[12];
      }
#      print "r/s @ $tmp[0]: $iostat{$tmp[0]}{'rs'}[$x-1] -> $x\n";
#      print "w/s @ $tmp[0]: $iostat{$tmp[0]}{'ws'}[$x-1] -> $x\n";
#      print "rbK/s @ $tmp[0]: $iostat{$tmp[0]}{'rkBs'}[$x-1] -> $x\n";
#      print "wkB/s @ $tmp[0]: $iostat{$tmp[0]}{'wkBs'}[$x-1] -> $x\n";
#      print "svctm @ $tmp[0]: $iostat{$tmp[0]}{'svctm'}[$x-1] -> $x\n";

    # get disk statistics on Solaris
    }elsif ( $result[$i] =~ /^(\s+)((\d+)\.(\d+)(\s){1}){8}((\d+)(\s){1}){2}(\w+)/ ){

      my @tmp = split / /, $result[$i];
      $iostat{$tmp[11]}{'rs'}[$x-1] = $tmp[1];
      $iostat{$tmp[11]}{'ws'}[$x-1] = $tmp[2];
      $iostat{$tmp[11]}{'rkBs'}[$x-1] = $tmp[3];
      $iostat{$tmp[11]}{'wkBs'}[$x-1] = $tmp[4];
      $iostat{$tmp[11]}{'wait'}[$x-1] = $tmp[5];
      $iostat{$tmp[11]}{'svctm'}[$x-1] = $tmp[7] + $tmp[8];
#      print "r/s @ $tmp[11]: $iostat{$tmp[11]}{'rs'}[$x-1]\n";
#      print "w/s @ $tmp[11]: $iostat{$tmp[11]}{'ws'}[$x-1]\n";
#      print "rkB/s @ $tmp[11]: $iostat{$tmp[11]}{'rkBs'}[$x-1]\n";
#      print "wkB/s @ $tmp[11]: $iostat{$tmp[11]}{'wkBs'}[$x-1]\n";
#      print "svctm @ $tmp[11]: $iostat{$tmp[11]}{'svctm'}[$x-1]\n";

    # get ioawait on Linux
    }elsif ( $result[$i] =~ /^(\s){1}((\d){1,3}\.(\d){1,2}(\s){1}){5}(\d){1,3}\.(\d){1,2}(\s){1}$/ ){

      my @tmp = split / /, $result[$i];
      $iostat{'iowait'}[$x] = $tmp[4];
#      print "iowait: $iostat{'iowait'}[$x]\n";
      $x++;

    # get iowait on Solaris
    }elsif ( $result[$i] =~ /^(\s){1}((\d){1,3}(\s){1}){3}(\d){1,3}(\s){1}$/ ){

      my @tmp = split / /, $result[$i];
      $iostat{'iowait'}[$x] = $tmp[3];
#      print "iowait: $iostat{'iowait'}[$x]\n";
      $x++;

   # get disks errors on Solaris
   }elsif ( $result[$i] =~ /Soft\sErrors:/ ){
     my @tmp = split / /, $result[$i];
     $hdd = $tmp[0];
     if ($tmp[3] > $errors{$hdd}{'soft'}){
       $statuscode = "critical";
       $statustext .= " $hdd (Soft Errors: $tmp[3])";
     }
     if ($tmp[6] > $errors{$hdd}{'hard'}){
       $statuscode = "critical";
       $statustext .= " $hdd (Hard Errors: $tmp[6])";
     }
     if ($tmp[9] > $errors{$hdd}{'transport'}){
       $statuscode = "critical";
       $statustext .= " $hdd (Transport Errors: $tmp[9])";
     }
     $errors{$hdd}{'soft'} = $tmp[3];
     $errors{$hdd}{'hard'} = $tmp[6];
     $errors{$hdd}{'transport'} = $tmp[9];
   }elsif ( $result[$i] =~ /^Media\sError:/ ){
     my @tmp = split / /, $result[$i];
     if ($tmp[2] > $errors{$hdd}{'media'}){
       $statuscode = "critical";
       $statustext .= " $hdd (Media Errors: $tmp[2])";
     }
     if ($tmp[6] > $errors{$hdd}{'drive'}){
       $statuscode = "critical";
       $statustext .= " $hdd (Drive Not Ready: $tmp[6])";
     }
     if ($tmp[9] > $errors{$hdd}{'nodev'}){
       $statuscode = "critical";
       $statustext .= " $hdd (No Device: $tmp[9])";
     }
     if ($tmp[11] > $errors{$hdd}{'recoverable'}){
       $statuscode = "warning" if $statuscode ne "critical";
       $statustext .= " $hdd (Recoverable: $tmp[11])";
     }
     $errors{$hdd}{'media'} = $tmp[2];
     $errors{$hdd}{'drive'} = $tmp[6];
     $errors{$hdd}{'nodev'} = $tmp[9];
     $errors{$hdd}{'recoverable'} = $tmp[11];
   }elsif ( $result[$i] =~ /^Illegal\sRequest:/ ){
     my @tmp = split / /, $result[$i];
     if ($tmp[2] > $errors{$hdd}{'illegal'}){
       $statuscode = "critical";
       $statustext .= " $hdd (Illegal Requests: $tmp[2])";
     }
     $errors{$hdd}{'illegal'} = $tmp[2];
   }
}

if (defined $o_errors){
  foreach my $disk (keys %errors){
    # write errors to file
    if (! open (TMPERRORS, ">$tmp_errors" . "_" . $disk) ){
      print "File $tmp_errors" . "_" . "$disk isn't writeable!\n";
      exit $ERRORS{$status{'unknown'}};
    }
    foreach my $param (keys %{ $errors{$disk} }){
      print TMPERRORS $param . " $errors{$disk}{$param}\n";
      $perfstats .= "'" . $disk . "_" . $param . "'=$errors{$disk}{$param}c;;;0; ";
    }
    close (TMPERRORS);
  }
}


# do some calculations

# iowait
my $value = undef;
$value = max @{ $iostat{'iowait'} } if defined $o_max;
$value = (sum @{ $iostat{'iowait'} }) / (scalar @{ $iostat{'iowait'} }) if ! defined $o_max;
$perfstats .= "'iowait'=$value%;$warn[2];$crit[2];0;100 ";

if ($value >= $crit[2]){
  $statuscode = 'critical';
  $statustext .= " iowait: $value,";
}elsif ($value >= $warn[2]){
  $statuscode = 'warning';
  $statustext .= " iowait: $value," if $statuscode ne 'critical';
  $statustext .= " iowait: $value," if $o_verbose >= 1 && $statuscode eq 'critical';
}else{
  $statuscode = 'ok' if $statuscode ne 'critical' && $statuscode ne 'warning';
  $statustext .= " iowait: $value," if $o_verbose >= 1;
}


# disk statistics
foreach my $disk (keys %iostat){
  next if $disk eq 'iowait';
  my ($rs, $ws) = undef;
  foreach my $param (keys %{ $iostat{$disk} }){
    # remove first entry when using multiple runs
    shift @{ $iostat{$disk}{$param} } if $o_runs > 1;
    $value = max @{ $iostat{$disk}{$param} } if defined $o_max;
    $value = (sum @{ $iostat{$disk}{$param} }) / (scalar @{ $iostat{$disk}{$param} }) if ! defined $o_max;
    if ($param eq "rs"){
      $rs = $value;
      $perfstats .= "'" . $disk . "_r/s'=$value;$warn[0];$crit[0];0; ";
    }elsif ($param eq "ws"){
      $ws = $value;
      $perfstats .= "'" . $disk . "_w/s'=$value;$warn[0];$crit[0];0; ";
    }elsif ($param eq "rkBs"){
      $perfstats .= "'" . $disk . "_rkB/s'=$value" . "KB;;;0; ";
    }elsif ($param eq "wkBs"){
      $perfstats .= "'" . $disk . "_wkB/s'=$value" . "KB;;;0; ";
    }elsif ($param eq "wait"){
      $perfstats .= "'" . $disk . "_wait'=$value" . "ms;;;0; ";
    }elsif ($param eq "svctm"){
      ($statuscode,$statustext) = get_status($value,$warn[1],$crit[1],$disk,$param);
      $perfstats .= "'" . $disk . "_svctm'=$value;$warn[1];$crit[1];0; ";
    }
  }
  my $tps = $rs + $ws;
  ($statuscode,$statustext) = get_status($tps,$warn[0],$crit[0],$disk,"tps")
}

$statustext = " on all disks." if $statuscode eq 'ok' && $o_verbose == 0;
$statustext .= $perfstats if $perfdata == 1;
exit_plugin($statuscode,$statustext);


#***************************************************#
#  Function get_status                              #
#---------------------------------------------------#
#  Matches value againts warning and critical       #
#  ARG1: value                                      #
#  ARG2: warning                                    #
#  ARG3: critical                                   #
#  ARG4: disk                                       #
#  ARG5: parameter                                  #
#***************************************************#

sub get_status{
  if ($_[0] >= $_[2]){
    $statuscode = 'critical';
    $statustext .= " $_[3] ($_[4]: $_[0]),";
  }elsif ($_[0] >= $_[1]){
    $statuscode = 'warning';
    $statustext .= " $_[3] ($_[4]: $_[0])," if $statuscode ne 'critical';
    $statustext .= " $_[3] ($_[4]: $_[0])," if $o_verbose >= 1 && $statuscode eq 'critical';
  }else{
    $statuscode = 'ok' if $statuscode ne 'critical' && $statuscode ne 'warning';
    $statustext .= " $_[3] ($_[4]: $_[0])," if $o_verbose >= 1;
  }
  return ($statuscode,$statustext);
}

#***************************************************#
#  Function exit_plugin                             #
#---------------------------------------------------#
#  Prints plugin output and exits with exit code.   #
#  ARG1: status code (ok|warning|cirtical|unknown)  #
#  ARG2: additional information                     #
#***************************************************#

sub exit_plugin{
  print "I/O $status{$_[0]}:$_[1]\n";
  exit $ERRORS{$status{$_[0]}};
}


exit $ERRORS{$status{'unknown'}};
