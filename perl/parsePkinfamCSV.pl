#!/usr/bin/perl
use strict;
use warnings;
use Text::CSV;

my $csv = Text::CSV->new ({
	binary    => 1, # Allow special character. Always set this
	auto_diag => 1, # Report irregularities immediately
});

open my $fh, "<", "pkinfam kinase database.csv";
my $family;
while(my $row = $csv->getline ($fh)) {
#	Experiment name,folder name,submitter,affiliation,date,cell line,species,vendor
#   date needs to be in the format of yyyy/mm/dd
	my @elmt=@$row;
	if(index($elmt[0],"=====")>-1){#the begin line of family definition
		my ($familyStr) = @{$csv->getline($fh)};
#		print "$familyStr\n";
		my @tmp = split(":",$familyStr);
		if (scalar @tmp==1){
			if ($tmp[0]=~/^(\S+)/){
				$family = $1;
			}
		}else{
			if($tmp[0] eq "Atypical"){
				#$family = substr($tmp[1],1);
				$family = $familyStr;
			}else{
				if ($tmp[0]=~/^(\S+)/){
					$family = $1;
				}
			}
		}
#		print "<$family>\t".length ($family)."\n";
		$csv->getline($fh);
		next;
	}
	next if(length($elmt[0])==0);
	if(index($elmt[0],"----")>-1){
		while($csv->getline($fh)){1}
		next;
	}
	if ($elmt[0]=~/^(\S+)\s+(\S+_HUMAN)\s*\(\S+\s*\)/){
		print "$1\t$2\t$family\n";
	}
}
