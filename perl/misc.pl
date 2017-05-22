#!/usr/bin/perl
use strict;
use warnings;
use Cwd 'abs_path';

sub getDBI(){
	my $abs_path = abs_path(__FILE__);#as it is called within another perl, $0 will be referred to the caller and __FILE__ is more suitable
	my $idx = index($abs_path,"misc.pl");#the file name is fixed, so safe to get the path in this way also platform independant
	my $path = substr($abs_path,0,$idx);
#	print "misc.pl file path: $path\n";

	my $type = "localhost";
	$type = $_[0] if (scalar @_ == 1);
	open IN,"${path}credential.txt" or die "Cannot find the credential file in the same folder of this misc.pl file";

	my %setting;
	my $token="";
	while (my $line=<IN>){
		chomp $line;
		if($line=~/^\[(.+)\]$/){
			$token = $1;
		}elsif($line=~/^\s*$/){
		}else{
			my ($key,$value)=split("=",$line);
			$setting{$token}{$key}=$value;
		}
	}
	die "No credential information for the given type $type" unless (exists $setting{$type});
	my $host = $setting{$type}{'host'};
	my $user = $setting{$type}{'user'};
	my $password = $setting{$type}{'password'};
	my $handle = DBI->connect("dbi:mysql:ctam:$host:3306",$user,$password,{mysql_enable_utf8 => 1}) or die "Can't connect to the DB\n";
#    my $handle = database({ driver => 'mysql', database => 'ctam', username => $user, password => $password, host => $host, port => '3306' });
	$handle->{RaiseError} = 1;
	return $handle;
}

1