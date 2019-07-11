## Customize Makefile settings for fbcv
## 
## If you need to customize your Makefile, make
## changes here rather than in the main Makefile

######################################################
### Download and integrate the DPO component       ###
######################################################


DPO=https://raw.githubusercontent.com/FlyBase/drosophila-phenotype-ontology/master/dpo-simple.obo
components/dpo-simple.owl:
	echo "CHANGE DPO PURL!"
	@if [ $(MIR) = true ] && [ $(IMP) = true ]; then $(ROBOT) annotate -I $(DPO) --ontology-iri $(ONTBASE)/$@ \
		convert -o $@; fi

#####################################################################################
### Run ontology-release-runner instead of ROBOT as long as ROBOT is broken.      ###
#####################################################################################

# The reason command (and the reduce command) removed some of the very crucial asserted axioms at this point.
# That is why we first need to extract all logical axioms (i.e. subsumptions) and merge them back in after 
# The reasoning step is completed. This will be a big problem when we switch to ROBOT completely..

tmp/fbcv_terms.txt: $(SRC)
	$(ROBOT) query --use-graphs true -f csv -i $< --query ../sparql/fbcv_terms.sparql $@

tmp/asserted-subclass-of-axioms.obo: $(SRC) tmp/fbcv_terms.txt
	$(ROBOT) merge --input $< \
		filter --term-file tmp/fbcv_terms.txt --select "self object-properties anonymous parents" --axioms "logical" --preserve-structure false \
		convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@

tmp/source-merged.obo: $(SRC) tmp/asserted-subclass-of-axioms.obo
	$(ROBOT) merge --input $< \
		reason --reasoner ELK \
		remove --axioms equivalent \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o tmp/source-merged.owl.obo &&\
		grep -v ^owl-axioms tmp/source-merged.owl.obo > tmp/source-stripped.obo &&\
		cat tmp/source-stripped.obo | perl -0777 -e '$$_ = <>; s/name[:].*\nname[:]/name:/g; print' | perl -0777 -e '$$_ = <>; s/def[:].*\nname[:]/def:/g; print' > $@ &&\
		rm tmp/source-merged.owl.obo tmp/source-stripped.obo

oort: tmp/source-merged.obo
	ontology-release-runner --reasoner elk $< --no-subsets --skip-ontology-checks --allow-equivalent-pairs --simple --relaxed --asserted --allow-overwrite --outdir oort

#test_oort:
#	ontology-release-runner --reasoner elk tmp/source-merged-minimal.obo --no-subsets --skip-ontology-checks --allow-equivalent-pairs --simple --allow-overwrite --outdir oort_test

$(ONT)-simple.owl: oort
	$(ROBOT) merge --input oort/$(ONT)-simple.obo \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		reduce \
		convert -o $@

$(ONT)-simple.obo: oort
	$(ROBOT) merge --input oort/$(ONT)-simple.obo \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		reduce \
		convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@
	
s:
	$(ROBOT) merge --input oort/$(ONT)-simple.obo \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		reduce \
		convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o ../../$(ONT)-simple.obo

$(ONT)-flybase.owl:
	owltools fbcv-simple.obo --make-subset-by-properties part_of conditionality -o $@

#$(ONT)-simple-x.owl:
#	$(ROBOT) merge --input tmp/source-merged.obo $(patsubst %, -i %, $(OTHER_SRC)) \
#		reason --reasoner ELK \
##		remove --axioms equivalent \
#		relax \
#		reduce -r ELK \
#		annotate --ontology-iri $(ONTBASE)/$@ --version-iri $(ONTBASE)/releases/$(TODAY)/$@ --output $@.tmp.owl && mv $@.tmp.owl $@


######################################################
### Code for generating additional FlyBase reports ###
######################################################

REPORT_FILES := $(REPORT_FILES) reports/obo_track_new_simple.txt reports/onto_metrics_calc.txt #reports/chado_load_check_simple.txt

SIMPLE_PURL =	http://purl.obolibrary.org/obo/fbcv/fbcv-simple.obo
LAST_DEPLOYED_SIMPLE=tmp/$(ONT)-simple-last.obo

$(LAST_DEPLOYED_SIMPLE):
	wget -O $@ $(SIMPLE_PURL)

flybase_script_base=https://raw.githubusercontent.com/FlyBase/drosophila-anatomy-developmental-ontology/master/tools/release_and_checking_scripts/releases/
onto_metrics_calc=$(flybase_script_base)onto_metrics_calc.pl
chado_load_checks=$(flybase_script_base)chado_load_checks.pl
obo_track_new=$(flybase_script_base)obo_track_new.pl
auto_def_sub=$(flybase_script_base)auto_def_sub.pl

install_flybase_scripts:
	cp ../scripts/OboModel.pm /usr/local/lib/perl5/site_perl
	wget -O ../scripts/onto_metrics_calc.pl $(onto_metrics_calc) && chmod +x ../scripts/onto_metrics_calc.pl
	#wget -O ../scripts/chado_load_checks.pl $(chado_load_checks) && chmod +x ../scripts/chado_load_checks.pl
	wget -O ../scripts/obo_track_new.pl $(obo_track_new) && chmod +x ../scripts/obo_track_new.pl
	wget -O ../scripts/auto_def_sub.pl $(auto_def_sub) && chmod +x ../scripts/auto_def_sub.pl
	echo "!!!!!Chado load checks currently not run!!!!!!!"

reports/obo_track_new_simple.txt: $(LAST_DEPLOYED_SIMPLE) install_flybase_scripts $(ONT)-simple.obo
	echo "Comparing with: "$(SIMPLE_PURL) && ../scripts/obo_track_new.pl $(LAST_DEPLOYED_SIMPLE) $(ONT)-simple.obo > $@

reports/robot_simple_diff.txt: #$(LAST_DEPLOYED_SIMPLE) #$(ONT)-simple.obo
	$(ROBOT) diff --left $(ONT)-simple.obo --right $(LAST_DEPLOYED_SIMPLE) --output $@

reports/onto_metrics_calc.txt: $(ONT)-simple.obo install_flybase_scripts
	../scripts/onto_metrics_calc.pl 'phenotypic_class' $(ONT)-simple.obo > $@
	
reports/chado_load_check_simple.txt: $(ONT)-simple.obo install_flybase_scripts
	../scripts/chado_load_checks.pl $(ONT)-simple.obo > $@

all_reports: all_reports_onestep $(REPORT_FILES)
ASSETS := $(ASSETS) components/dpo-simple.owl

prepare_release: $(ASSETS) $(PATTERN_RELEASE_FILES)
	rsync -R $(ASSETS) $(RELEASEDIR) &&\
  echo "Release files are now in $(RELEASEDIR) - now you should commit, push and make a release on github"
	
#####################################################################################
### Regenerate placeholder definitions                                            ###
#####################################################################################
# There are two types of definitions that FBCV uses: "." (DOT-) definitions are those for which the formal 
# definition is translated into a human readable definitions. "$sub_" (SUB-) definitions are those that have 
# special placeholder string to substitute in definitions from external ontologies, mostly CHEBI

auto_generated_definitions_seed_dot.txt: $(SRC)
	$(ROBOT) query --use-graphs false -f csv -i $(SRC) --query ../sparql/dot-definitions.sparql $@.tmp &&\
	cat $@.tmp | sort | uniq >  $@
	rm -f $@.tmp
	
auto_generated_definitions_seed_sub.txt: $(SRC)
	$(ROBOT) query --use-graphs false -f csv -i $(SRC) --query ../sparql/classes-with-placeholder-definitions.sparql $@.tmp &&\
	cat $@.tmp | sort | uniq >  $@
	rm -f $@.tmp

tmp/merged-source-pre.owl: $(SRC)
	$(ROBOT) merge -i $(SRC) -i mirror/chebi.owl --output $@

auto_generated_definitions_dot.owl: tmp/merged-source-pre.owl auto_generated_definitions_seed_dot.txt
	java -jar ../scripts/eq-writer.jar $< auto_generated_definitions_seed_dot.txt flybase $@ NA

auto_generated_definitions_sub.owl: tmp/merged-source-pre.owl auto_generated_definitions_seed_sub.txt
	java -jar ../scripts/eq-writer.jar $< auto_generated_definitions_seed_sub.txt sub_external $@ NA

pre_release: $(ONT)-edit.obo auto_generated_definitions_dot.owl auto_generated_definitions_sub.owl components/dpo-simple.owl
	cp $(ONT)-edit.obo tmp/$(ONT)-edit-release.obo
	sed -i '/def[:] \"[.]\"/d' tmp/$(ONT)-edit-release.obo
	sed -i '/sub_/d' tmp/$(ONT)-edit-release.obo
	$(ROBOT) merge -i tmp/$(ONT)-edit-release.obo -i auto_generated_definitions_dot.owl -i auto_generated_definitions_sub.owl --collapse-import-closure false -o $(ONT)-edit-release.ofn && mv $(ONT)-edit-release.ofn $(ONT)-edit-release.owl
	echo "Preprocessing done. Make sure that NO CHANGES TO THE EDIT FILE ARE COMMITTED!"
	
post_release: $(ONT)-flybase.owl
	cp $(ONT)-flybase.owl ../..
	