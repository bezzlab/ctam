#!/usr/bin/perl
use strict;
use warnings;
use DBD::mysql;
use Data::Dumper;
use utf8;
require "misc.pl";
binmode(STDOUT, ":utf8");
#print "GSK-3 α/β"; ###NOTE: in the command prompt, need to type chcp 65001 to set prompt into utf8
#exit;
#then need to make sure mysql connection is utf8-compatiable https://en.wikibooks.org/wiki/Perl_Programming/Unicode_UTF-8
#To check utf8 character in mysql command line, remember to use option --default_character_set=utf8
#my $dbi = &getDBI("gio2 insert");
my $dbi = &getDBI("localhost");
my $handleCheck = $dbi->prepare("select * from regulator where id=?");
my $handleUpdate = $dbi->prepare("update regulator set name=?, CAS=?, formula=?, mw=?, main_target=?,activity_link=? where id =?");
my $handleInsert = $dbi->prepare("insert into regulator values (?,?,?,?,?,?,?)");
my $kinaseCheck = $dbi->prepare("select * from kinase where protein_id = ?");
my $relationshipInsert = $dbi->prepare("insert into regulator_kinase values (?,?)");
open my $fh, "<:encoding(utf-8)", "inhibitor table data Mar 2017.txt";
#open my $fh, "<:encoding(utf-8)", "inhibitor table data Jan 2017 8 batches.txt";#read in file in utf8 mode
my $count=0;
while (my $line=<$fh>){
	$count++;
	chomp($line);
	my @arr = split("\t",$line);
	#0: index, 1: name, 2: CAS number, 3: formula, 4: molecular weight, 5: main target, 6:main target as Uniprot, 7: activity link
	unless(length $arr[6]==0){
		my @elmts = split(";",$arr[6]);
		foreach my $elmt(@elmts){
			if ($elmt=~/(\S+_HUMAN)/){
				my $found = $kinaseCheck->execute($1);
				if ($found == 0){
					print "$count inhibits <$1> which is not found in the kinase list\n";
				}else{
					$relationshipInsert->execute($count,$1);
				}
			}
		}
#		print "$count: name <$arr[1]> CAS <$arr[2]> formula <$arr[3]> MW <$arr[4]> target <$arr[5]> kinase <$arr[6]> link <$arr[7]>\n";
	}
#	next; #uncomment to only populate the regulator_kinase table
	my $exist = $handleCheck->execute($count);
	if($exist == 1){
		if ($arr[7] eq "null"){
			$handleUpdate->execute($arr[1],$arr[2],$arr[3],$arr[4],$arr[5],undef,$count);
		}else{
			$handleUpdate->execute($arr[1],$arr[2],$arr[3],$arr[4],$arr[5],$arr[7],$count);
		}
	}else{
		if ($arr[7] eq "null"){
			$handleInsert->execute($count,$arr[1],$arr[2],$arr[3],$arr[4],$arr[5],undef);
		}else{
			$handleInsert->execute($count,$arr[1],$arr[2],$arr[3],$arr[4],$arr[5],$arr[7]);
		}
	}
}