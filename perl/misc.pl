#!/usr/bin/perl
use strict;
use warnings;

sub getDBI(){
	my $type = "localhost";
	$type = $_[0] if (scalar @_ == 1);
	open IN,"credential.txt" or die "Cannot find the credential file";
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
	my $handle = DBI->connect("dbi:mysql:ctam:$host:3306",$user,$password) or die "Can't connect to the DB\n";
	return $handle;
}

1