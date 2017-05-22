#!/usr/bin/perl
use strict;
use warnings;
use DBD::mysql;
use Text::CSV;
require "..//metadata//misc.pl";

#IMPORTANT: the NULL value (empty value) in MySQL will be retrieved as "" in perl (length = 0)
#this script is based on the converted CSV by Pescal++ from Mascot identification result .dat file or converted mzIdentML file
#therefore there are hard-coded parts, e.g. the CSV file layout (header order), Mascot:score as peptide score etc.
$"=">,<";#set array element separator
$|=1;#set autoflush, i.e. print instantly into non-stdout pipe

my $numArg = scalar @ARGV;
#unless ($numArg == 1 || $numArg == 2){
unless ($numArg == 1){
	print "Usage: savePhosphoSite.pl <experiment id>\n";
	print "Experiment id is a positive integer value\n";
	exit;
}

my $exp_id = $ARGV[0];
my $method = "column";#$ARGV[1];
my $file = "statistical_result_using_${method}_experiment_${exp_id}.csv";
#$file = "statistical_result_using_${method}_experiment_16.csv";
my $dbi = &getDBI("gio2 insert");
#my $dbi = &getDBI();#subroutine in misc.pl
#my $dbi = &getDBI("gio2 query");#subroutine in misc.pl
my $csv = Text::CSV->new ({
	binary    => 1, # Allow special character. Always set this
	auto_diag => 1, # Report irregularities immediately
});

#get all peptides from the database for the given experiment
my $peptideAllByExperimentStr = "select p.id, p.sequence ,p.protein, p.charge, p.modification_str from peptide p, peptide_in_experiment pe where pe.experiment_id = ? and pe.peptide_id=p.id order by p.sequence asc, p.id asc";
my %peptideIDs;
my $handle = $dbi->prepare($peptideAllByExperimentStr);
$handle->execute($exp_id);
while (my ($pep_id,$seq,$pro,$charge,$mod)=$handle->fetchrow_array()){
	$peptideIDs{"$seq;$pro;$charge;$mod"}=$pep_id;
}
print "There are ".(scalar keys %peptideIDs)." peptides\n";

#get all cell lines for the given experiment
my $experimentCellLineStr = "select cl.name,clu.id from experiment_cell_line ecl,cell_line cl, cell_line_used clu where ecl.experiment_id = ? and ecl.cell_line_used_id = clu.id and clu.cell_line_id = cl.id";
my %cellLineIDs;
$handle = $dbi->prepare($experimentCellLineStr);
$handle->execute($exp_id);
while( my ($cell_name,$cell_line_used_id)=$handle->fetchrow_array()){
	$cellLineIDs{$cell_name}=$cell_line_used_id;
#	print "<$cell_name>\t<$cell_line_used_id>\n";
}

#get run list for the given experiment
my $insertHandle = $dbi->prepare("insert into final_result values(?,?,?,?,?,?,?)");
my $runInExperimentStr = "select r.id, rie.group, rcl.cell_line_used_id from run r,runs_in_experiment rie,run_cell_line rcl where r.id=rcl.run_id and rcl.run_id = rie.run_id and rie.experiment_id = $exp_id";
$handle=$dbi->prepare($runInExperimentStr);
$handle->execute();
my %runInGroupAndCell;#as name suggested, the hash has first key of cell line and second key of group and the values are array of related run ids
while (my ($run_id,$group, $cell_line_used_id)=$handle->fetchrow_array()){
	push(@{$runInGroupAndCell{$cell_line_used_id}{$group}},$run_id);
#	print "<$run_id>\t<$group>\t<$cell_line_used_id>\n";
}

#
my $psmCountHandle = $dbi->prepare("select distinct p.id from psm p, identification i where p.identification_id = i.id and i.run_id = ? and p.peptide = ? and charge = ?");
my $modificationHandle = $dbi->prepare("select display from modification m, psm_modification pm where pm.psm_id = ? and pm.modification_id = m.id");

foreach my $cell_line_used_id(keys %runInGroupAndCell){
	my %hash = %{$runInGroupAndCell{$cell_line_used_id}};
	foreach my $group (keys %hash){
		my @a=@{$hash{$group}};
		print "$cell_line_used_id $group: <@a>\n";
	}
	next unless (exists $hash{"control"});
	foreach my $peptide_info(keys %peptideIDs){
		my ($peptide,$protein,$charge,$modification) = split(";",$peptide_info);
		my $peptide_id = $peptideIDs{$peptide_info};
		my $count = 0;
		foreach my $run_id(@{$hash{"control"}}){
			$psmCountHandle->execute($run_id,$peptide,$charge); 
			while (my $psm_id=$psmCountHandle->fetchrow_array()){
				my %modHash;
				$modificationHandle->execute($psm_id);
				while (my $display = $modificationHandle->fetchrow_array()){
					$modHash{$display}++;
				}
				my $mod_str="";
				foreach my $display(sort {$a cmp $b} keys %modHash){
					my $num = $modHash{$display};
					if($num!=1){
						$mod_str.="$num ";
					}
					$mod_str.="$display; "
				}
				my $len = length($mod_str);
				$mod_str = substr($mod_str,0,$len-2) if ($len>0);
				$count++ if ($mod_str eq $modification); 
			}
		}
#	print "insert into final_result values($peptide_id,$exp_id,$cell_id,\"$group\",$fold,$adjusted_pvalue,0);\n";
		$insertHandle->execute($peptide_id,$exp_id,$cell_line_used_id,"control",1,1,$count) if($count>0);
	}
}

#For query type the query columns are listed
#The database handles for experiment level
print "Now parse $file and import into database\n";
open my $fh, "<", "$file";
#open my $fh, "<", "samplePhosphositeList.txt";
my $count=0;
$csv->getline ($fh);#remove header
while(my $row = $csv->getline ($fh)) {
	$count++;
	print "Processed $count records\n" if (($count%500)==0);
	my @arr = @$row;
	my (undef,$group,$cell,$peptide,$protein,$charge,$modification,$fold,$pvalue,$adjusted_pvalue,$control_mean,$control_count,$treatment_mean,$treatment_count)=@arr;
	next if($control_count==0 && $treatment_count==0);#no data available, skipped
	next if($control_count==1 && $treatment_count==0);#only one control data, could be noise, skipped
	next if($control_count==0 && $treatment_count==1);

	my $peptide_id = $peptideIDs{"$peptide;$protein;$charge;$modification"};
#	my $group_id;
	my $cell_id = $cellLineIDs{$cell};
#	print "<$exp_id>\t<$peptide_id>\t<$group>\t<$cell_id>\n";
	$fold =~s/Inf/100000000/;
	$adjusted_pvalue=~s/NA/10/;
	my $count = 0;
	foreach my $run_id(@{$runInGroupAndCell{$cell_id}{$group}}){
		$psmCountHandle->execute($run_id,$peptide,$charge); 
		while (my $psm_id=$psmCountHandle->fetchrow_array()){
			my %hash;
			$modificationHandle->execute($psm_id);
			while (my $display = $modificationHandle->fetchrow_array()){
				$hash{$display}++;
			}
			my $mod_str="";
			foreach my $display(sort {$a cmp $b} keys %hash){
				my $num = $hash{$display};
				if($num!=1){
					$mod_str.="$num ";
				}
				$mod_str.="$display; "
			}
			my $len = length($mod_str);
			$mod_str = substr($mod_str,0,$len-2) if ($len>0);
			$count++ if ($mod_str eq $modification); 
		}
	}
#	print "insert into final_result values($peptide_id,$exp_id,$cell_id,\"$group\",$fold,$adjusted_pvalue,0);\n";
	$insertHandle->execute($peptide_id,$exp_id,$cell_id,$group,$fold,$adjusted_pvalue,$count);
}

