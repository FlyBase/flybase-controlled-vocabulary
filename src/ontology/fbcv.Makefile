## Customize Makefile settings for fbcv
## 
## If you need to customize your Makefile, make
## changes here rather than in the main Makefile

# These date variables can be overwritten by the script calling this makefile, for example
# sh run.sh make DATE="2019-01-01" somegoal

DATE   ?= $(shell date +%Y-%m-%d)
DATETIME ?= $(shell date +"%d:%m:%Y %H:%M")

######################################################
### Download and integrate the DPO component       ###
######################################################

DPO=http://purl.obolibrary.org/obo/dpo/dpo-simple.owl

components/dpo-simple.owl: .FORCE
	wget $(DPO) && mv dpo-simple.owl tmp/dpo-simple.owl
	$(ROBOT) annotate -i tmp/dpo-simple.owl --ontology-iri $(ONTBASE)/$@ --version-iri $(ONTBASE)/releases/$(TODAY)/$@ -o $@
	rm tmp/dpo-simple.owl

#####################################################################################
### Run ontology-release-runner instead of ROBOT as long as ROBOT is broken.      ###
#####################################################################################

# The reason command (and the reduce command) removed some of the very crucial asserted axioms at this point.
# That is why we first need to extract all logical axioms (i.e. subsumptions) and merge them back in after 
# The reasoning step is completed. This will be a big problem when we switch to ROBOT completely..

tmp/fbcv_terms.txt: $(SRC)
	$(ROBOT) query --use-graphs true -f csv -i $(SRC) --query ../sparql/fbcv_terms.sparql $@

tmp/asserted-subclass-of-axioms.obo: $(SRC) tmp/fbcv_terms.txt
	$(ROBOT) merge --input $(SRC) \
		filter --term-file tmp/fbcv_terms.txt --axioms "logical" --preserve-structure false \
		convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@

#		

tmp/source-merged.obo: $(SRC) tmp/asserted-subclass-of-axioms.obo
	$(ROBOT) merge --input $(SRC) \
		reason --reasoner ELK \
		relax \
		remove --axioms equivalent \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o tmp/source-merged.owl.obo &&\
		grep -v ^owl-axioms tmp/source-merged.owl.obo > tmp/source-stripped.obo &&\
		cat tmp/source-stripped.obo | perl -0777 -e '$$_ = <>; s/name[:].*\nname[:]/name:/g; print' | perl -0777 -e '$$_ = <>; s/def[:].*\ndef[:]/def:/g; print' > $@ &&\
		rm tmp/source-merged.owl.obo tmp/source-stripped.obo

oort: tmp/source-merged.obo
	ontology-release-runner --reasoner elk $< --no-subsets --skip-ontology-checks --allow-equivalent-pairs --simple --relaxed --asserted --allow-overwrite --outdir oort

tmp/$(ONT)-stripped.owl: oort
	$(ROBOT) filter --input oort/$(ONT)-simple.owl --term-file tmp/fbcv_terms.txt --trim false \
		convert -o $@

# fbcv_signature.txt should contain all FBCV terms and all properties (and subsets) used by the ontology.
# It serves like a proper signature, but including annotation properties
tmp/fbcv_signature.txt: tmp/$(ONT)-stripped.owl tmp/fbcv_terms.txt
	$(ROBOT) query -f csv -i $< --query ../sparql/object-properties.sparql $@_prop.tmp &&\
	cat tmp/fbcv_terms.txt $@_prop.tmp | sort | uniq > $@ &&\
	rm $@_prop.tmp

# The standard simple artefacts keeps a bunch of irrelevant Typedefs which are a result of the merge. The following steps takes the result
# of the oort simple version, and then removes them. A second problem is that oort does not deal well with cycles and removes some of the 
# asserted FBCV subsumptions. This can hopefully be solved once we can move all the way to ROBOT, but for now, it requires merging in
# the asserted hierarchy and reducing again.


# Note that right now, TypeDefs that are FBCV native (like has_age) are included in the release!

$(ONT)-simple.owl: oort tmp/fbcv_signature.txt
	$(ROBOT) merge --input oort/$(ONT)-simple.owl \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		reason --reasoner ELK --equivalent-classes-allowed asserted-only \
		relax \
		remove --axioms equivalent \
		relax \
		filter --term-file $(SIMPLESEED) --select "annotations ontology anonymous self" --trim true --signature true \
		remove --term-file tmp/fbcv_signature.txt --select complement --trim false \
		reduce -r ELK \
		annotate --ontology-iri $(ONTBASE)/$@ --version-iri $(ONTBASE)/releases/$(TODAY)/$@ --annotation oboInOwl:date "$(OBODATE)" --output $@.tmp.owl && mv $@.tmp.owl $@

ontsim:
	$(ROBOT) merge --input oort/$(ONT)-simple.owl \
		merge -i tmp/asserted-subclass-of-axioms.obo \
		reason --reasoner ELK --equivalent-classes-allowed asserted-only \
		relax \
		filter --term-file $(SIMPLESEED) --select "annotations ontology anonymous self" --trim true --signature true \
		remove --term-file tmp/fbcv_signature.txt --select complement --trim false \
		reduce -r ELK \
		annotate --ontology-iri $(ONTBASE)/$@ --version-iri $(ONTBASE)/releases/$(TODAY)/$@ --annotation oboInOwl:date "$(OBODATE)" --output $@.tmp.owl && mv $@.tmp.owl $@


#$(ONT)-simple.obo: oort
#	$(ROBOT) merge --input oort/$(ONT)-simple.obo \
#		merge -i tmp/asserted-subclass-of-axioms.obo \
#		reduce \
#		remove --term-file tmp/fbcv_signature.txt --select complement --trim false \
#		convert -o $@
#$(ONT)-simple.obo: oort

# the fbcv-flybase target is a massive hack that 

$(ONT)-flybase.obo:
	$(ROBOT) remove --input $(ONT)-simple.obo --term "http://purl.obolibrary.org/obo/FBcv_0008000" \
		convert -o $@
	sed -i '/^date[:]/c\date: $(DATETIME)' $@
	sed -i '/^data-version[:]/c\data-version: $(DATE)' $@
	sed -i '/FlyBase_miscellaneous_CV/d' $@

# The following lines were part of a previous misconception that we needed a part_of typedef for the flybase release.
#	echo "[Typedef]" >> $@
#	echo "id: part_of" >> $@
#	echo "name: part_of" >> $@
#	echo "namespace: relationship" >> $@
#	echo 'synonym: "part_of" EXACT []' >> $@
#	echo "xref: BFO:0000050" >> $@
#	echo "xref_analog: OBO_REL:part_of" >> $@
#	echo "is_transitive: true" >> $@

#	owltools $(ONT)-simple --make-subset-by-properties part_of conditionality -o $@

######################################################
### Code for generating additional FlyBase reports ###
######################################################

REPORT_FILES := $(REPORT_FILES) reports/obo_track_new_simple.txt  reports/robot_simple_diff.txt reports/onto_metrics_calc.txt reports/chado_load_check_simple.txt

SIMPLE_PURL =	http://purl.obolibrary.org/obo/fbcv/fbcv-simple.obo
LAST_DEPLOYED_SIMPLE=tmp/$(ONT)-simple-last.obo

$(LAST_DEPLOYED_SIMPLE):
	wget -O $@ $(SIMPLE_PURL)

obo_model=https://raw.githubusercontent.com/FlyBase/flybase-controlled-vocabulary/master/external_tools/perl_modules/releases/OboModel.pm
flybase_script_base=https://raw.githubusercontent.com/FlyBase/drosophila-anatomy-developmental-ontology/master/tools/release_and_checking_scripts/releases/
onto_metrics_calc=$(flybase_script_base)onto_metrics_calc.pl
chado_load_checks=$(flybase_script_base)chado_load_checks.pl
obo_track_new=$(flybase_script_base)obo_track_new.pl
auto_def_sub=$(flybase_script_base)auto_def_sub.pl

install_flybase_scripts:
	wget -O ../scripts/OboModel.pm $(obo_model)
	cp ../scripts/OboModel.pm /usr/local/lib/perl5/site_perl
	wget -O ../scripts/onto_metrics_calc.pl $(onto_metrics_calc) && chmod +x ../scripts/onto_metrics_calc.pl
	wget -O ../scripts/chado_load_checks.pl $(chado_load_checks) && chmod +x ../scripts/chado_load_checks.pl
	wget -O ../scripts/obo_track_new.pl $(obo_track_new) && chmod +x ../scripts/obo_track_new.pl
	wget -O ../scripts/auto_def_sub.pl $(auto_def_sub) && chmod +x ../scripts/auto_def_sub.pl
	echo "Warning: Chado load checks currently exclude ISBN wellformedness checks!"

reports/obo_track_new_simple.txt: $(LAST_DEPLOYED_SIMPLE) install_flybase_scripts $(ONT)-simple.obo
	echo "Comparing with: "$(SIMPLE_PURL) && ../scripts/obo_track_new.pl $(LAST_DEPLOYED_SIMPLE) $(ONT)-simple.obo > $@

reports/robot_simple_diff.txt: $(LAST_DEPLOYED_SIMPLE) $(ONT)-simple.obo
	$(ROBOT) diff --left $(ONT)-simple.obo --right $(LAST_DEPLOYED_SIMPLE) --output $@

reports/onto_metrics_calc.txt: $(ONT)-simple.obo install_flybase_scripts
	../scripts/onto_metrics_calc.pl 'phenotypic_class' $(ONT)-simple.obo > $@
	
reports/chado_load_check_simple.txt: install_flybase_scripts $(ONT)-flybase.obo 
	../scripts/chado_load_checks.pl $(ONT)-flybase.obo > $@

all_reports: all_reports_onestep $(REPORT_FILES)
ASSETS := $(ASSETS) components/dpo-simple.owl

prepare_release: $(ASSETS) $(PATTERN_RELEASE_FILES)
	rsync -R $(ASSETS) $(RELEASEDIR) &&\
  echo "Release files are now in $(RELEASEDIR) - now you should commit, push and make a release on github"
	
#####################################################################################
### Regenerate placeholder definitions         (Pre-release) pipelines            ###
#####################################################################################
# There are two types of definitions that FBCV uses: "." (DOT-) definitions are those for which the formal 
# definition is translated into a human readable definitions. "$sub_" (SUB-) definitions are those that have 
# special placeholder string to substitute in definitions from external ontologies, mostly CHEBI

tmp/auto_generated_definitions_seed_dot.txt: $(SRC)
	$(ROBOT) query --use-graphs false -f csv -i $(SRC) --query ../sparql/dot-definitions.sparql $@.tmp &&\
	cat $@.tmp | sort | uniq >  $@
	rm -f $@.tmp
	
tmp/auto_generated_definitions_seed_sub.txt: $(SRC)
	$(ROBOT) query --use-graphs false -f csv -i $(SRC) --query ../sparql/classes-with-placeholder-definitions.sparql $@.tmp &&\
	cat $@.tmp | sort | uniq >  $@
	rm -f $@.tmp

CHEBI=https://raw.githubusercontent.com/matentzn/large-ontology-dependencies/master/chebi.owl.gz

mirror/chebi.owl: mirror/chebi.trigger
	echo "WRONG CHEBI IS USED"
	@if [ $(MIR) = true ] && [ $(IMP) = true ]; then wget $(CHEBI) && mv chebi.owl.gz tmp/chebi.owl.gz && $(ROBOT) convert -i tmp/chebi.owl.gz -o $@.tmp.owl && mv $@.tmp.owl $@; fi
.PRECIOUS: mirror/%.owl

tmp/merged-source-pre.owl: $(SRC) mirror/chebi.owl
	$(ROBOT) merge -i $(SRC) -i mirror/chebi.owl --output $@

tmp/auto_generated_definitions_dot.owl: tmp/merged-source-pre.owl tmp/auto_generated_definitions_seed_dot.txt
	java -jar ../scripts/eq-writer.jar $< tmp/auto_generated_definitions_seed_dot.txt flybase $@ NA add_dot_refs

tmp/auto_generated_definitions_sub.owl: tmp/merged-source-pre.owl tmp/auto_generated_definitions_seed_sub.txt
	java -jar ../scripts/eq-writer.jar $< tmp/auto_generated_definitions_seed_sub.txt sub_external $@ NA source_xref

tmp/replaced_defs.txt:
	cat tmp/auto_generated_definitions_seed_sub.txt tmp/auto_generated_definitions_seed_dot.txt | sort | uniq > $@

pre_release: $(ONT)-edit.obo tmp/auto_generated_definitions_dot.owl tmp/auto_generated_definitions_sub.owl components/dpo-simple.owl
	cp $(ONT)-edit.obo tmp/$(ONT)-edit-release.obo
	sed -i '/def[:] \"[.]\"/d' tmp/$(ONT)-edit-release.obo
	sed -i '/sub_/d' tmp/$(ONT)-edit-release.obo
	$(ROBOT) merge -i tmp/$(ONT)-edit-release.obo -i tmp/auto_generated_definitions_dot.owl -i tmp/auto_generated_definitions_sub.owl --collapse-import-closure false -o $(ONT)-edit-release.ofn && mv $(ONT)-edit-release.ofn $(ONT)-edit-release.owl
	echo "Preprocessing done. Make sure that NO CHANGES TO THE EDIT FILE ARE COMMITTED!"
	
post_release: $(ONT)-flybase.obo
	cp $(ONT)-flybase.obo ../..
	
test_remove: $(ONT)-edit.obo tmp/replaced_defs.txt
	$(ROBOT) remove -i $(ONT)-edit.obo remove --term-file tmp/replaced_defs.txt --axioms annotation --trim false \ merge -i tmp/auto_generated_definitions_dot.owl -i tmp/auto_generated_definitions_sub.owl --collapse-import-closure false -o $(ONT)-edit-release.ofn && mv $(ONT)-edit-release.ofn $(ONT)-edit-release2.owl
	diff $(ONT)-edit-release2.owl $(ONT)-edit-release.owl
	
########################
##    TRAVIS       #####
########################


# The merge hack allows to add axioms to the ontology used for QC to allow it to pass some
# QC rule that is deemed irrelevant

obo_qc_%:
	$(ROBOT) merge -i $* -i components/qc_assertions.owl -o $@ &&\
	$(ROBOT) report -i $@ --profile qc-profile.txt --fail-on ERROR --print 5 -o $@.txt

obo_qc: obo_qc_$(ONT).obo obo_qc_$(ONT).owl

flybase_qc.owl: odkversion obo_qc
	$(ROBOT) merge -i $(ONT)-full.owl -i components/qc_assertions.owl -o $@

flybase_qc: flybase_qc.owl
	$(ROBOT) reason --input $< --reasoner ELK  --equivalent-classes-allowed asserted-only --output test.owl && rm test.owl && echo "Success"
