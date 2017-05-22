use ctam;
#cell line  id, name, species, source, growth, morphology, disease
insert into cell_line values (null, "HL-60", "Human", "Blood", "Suspension","Lymphoblast","Promyelocytic leukemia");
insert into cell_line values (null, "NTERA-2 clone D1", "Human", "Myeloma", "Adherent","Epithelial","Pluripotent embryonal adenocarcinoma");
insert into cell_line values (null, "MCF-7", "Human", "Breast adenocarcinoma", "Adherent","Epithelial","Breast adenocarcinoma");

#vendor		id, name, website
insert into vendor values (null, "Unknown",null);
insert into vendor values (null, "ATCC", "http://www.lgcstandards-atcc.org/Products/Cells_and_Microorganisms/Cell_Lines/");

#cell_line_used 	id, cell_line_id, vendor_id, vendor_product_id, link
insert into cell_line_used values (null,1,2,"",null,null,null);
insert into cell_line_used values (null,2,2,"",null,"CRL-1973","Human/Alphanumeric/CRL-1973.aspx");
insert into cell_line_used values (null,3,1,"",null,null,null);

#experiment id, submitter, affiliation, date, cell_line_used_id, description, processed
#insert into experiment values (null, "HL-60", "Maruan", "BCI", "2016-03-06", 1, "b1790p079-HL60-batch4",false);
#insert into experiment values (null, "NTERA-2", "Maruan", "BCI", "2016-03-06", 2, "b1790p079-NTERA2-batch4",false);
#insert into experiment values (null, "MCF-7", "Maruan", "BCI", "2016-03-06", 3, "b1790p079-MCF7-batch4",false);

#id AUTO_INCREMENT, name, spectral_file_name, spectral_file_format, spectral_file_location, spectral_repository_name, spectral_repository_accession
#insert into run values (null,"F001740","b1790p079_PP1_HL60_CHIR_r2.raw","RAW","D:\Maruan\b1790p079_Phospho1&2_hl60+ntera2+mcf7 (8 inhib)\b1790p079_PP1_HL60_CHIR_r2.raw",null,null);
#insert into run values (null,"F001741","b1790p079_PP1_HL60_DMSO_r1.raw","RAW","D:\Maruan\b1790p079_Phospho1&2_hl60+ntera2+mcf7 (8 inhib)\b1790p079_PP1_HL60_DMSO_r1.raw",null,null);

#run_id, experiment_id, role` VARCHAR(45) NOT NULL
#insert into runs_in_experiment values (1,1,"CHIR");
#insert into runs_in_experiment values (2,1,"Control");

#regulator  id AI, name, CAS, formula, mw, activity_link
#insert into regulator values (null, "CHIR-99021", "252917-06-9", "C22 H18 N8 Cl2",465.34,341051);
#insert into regulator values (null, "LY2090314", "603288-22-8", "C28 H25 F N6 O3",512.53,null);
#insert into regulator values (null, "BX-912", "702674-56-4", "C20 H23 Br N8 O",471.35,600888);
#insert into regulator values (null, "GSK2334470", "1227911-45-6", "C25 H34 N8 O",462.59,348819);
#insert into regulator values (null, "Ipatasertib(GDC-0068)", "1001264-89-6", "C24 H32 Cl N5 O2",458,null);
#insert into regulator values (null, "AZD5363", "1143532-39-1", "C21 H25 Cl N6 O2",428.92,null);
#insert into regulator values (null, "AZD1480", "935666-88-9", "C14 H14 Cl F N8",348.76,null);
#insert into regulator values (null, "Tasocitinib(CP-690550)", "540737-29-9", "C16 H20 N6 O",312.38,349397);

#insert into protein values ("P31946", "1433B_HUMAN", null, null);
#id, fasta_file, enzyme, peptide_tolerance, peptide_tolerance_unit, product_tolerance, product_tolerance_unit, miscleavage, min_charge, max_charge, species, species_taxo_id
#insert into search_parameter values (null,"SwissProt_Sep2014_2015_12.fasta","Trypsin",10,"ppm",0.025,"Dalton",null,null,null,"Human",9606);

#id, name, mw_shift, site, display, PSIMOD_accession, UNIMOD_accession
#http://psidev.cvs.sourceforge.net/viewvc/psidev/psi/mod/data/PSI-MOD.obo
#http://www.unimod.org/obo/unimod.obo
insert into modification values (null, "Oxidation",15.994915, "M", "Oxidation (M)","PSIMOD:00719","UNIMOD:35");
insert into modification values (null, "Carbamidomethyl",57.021464, "C", "Carbamidomethyl (C)","PSIMOD:01060","UNIMOD:4");
insert into modification values (null, "Gln->pyro-Glu",-17.026549, "N-term Q", "Gln->pyro-Glu (N-term Q)","PSIMOD:00040","UNIMOD:28");
insert into modification values (null, "Phospho",79.966331, "ST", "Phospho (ST)","PSIMOD:00046,PSIMOD:00047","UNIMOD:21");
insert into modification values (null, "Phospho",79.966331, "Y", "Phospho (Y)","PSIMOD:00048","UNIMOD:21");

#search_parameter_id, modification_id, is_fixed
#insert into search_parameter_modification values (1,1,False);
#insert into search_parameter_modification values (1,2,True);	
