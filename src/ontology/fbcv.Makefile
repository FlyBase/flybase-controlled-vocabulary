## Customize Makefile settings for fbcv
##
## If you need to customize your Makefile, make
## changes here rather than in the main Makefile

# These date variables can be overwritten by the script calling this makefile, for example
# sh run.sh make DATE="2019-01-01" somegoal

DATE   ?= $(shell date +%Y-%m-%d)
DATETIME ?= $(shell date +"%d:%m:%Y %H:%M")


.SECONDEXPANSION:
.PHONY: prepare_release
prepare_release: $$(ASSETS) release_reports
	rsync -R $(RELEASE_ASSETS) $(REPORT_FILES) $(FLYBASE_REPORTS) $(IMPORT_FILES) $(RELEASEDIR) &&\
	rm -f $(CLEANFILES)
	echo "Release files are now in $(RELEASEDIR) - now you should commit, push and make a release on your git hosting site such as GitHub or GitLab"

MAIN_FILES := $(MAIN_FILES) flybase_controlled_vocabulary.obo
CLEANFILES := $(CLEANFILES) $(patsubst %, $(IMPORTDIR)/%_terms_combined.txt, $(IMPORTS)) $(ONT)-edit-release.owl
.INTERMEDIATE: $(CLEANFILES)

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

tmp/source-merged.obo: $(EDIT_PREPROCESSED) tmp/asserted-subclass-of-axioms.obo
	$(ROBOT) merge --input $< \
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

# For some reason, using reduce just does not work on FBCV this is a workaround, but it needs some figuring out..

$(ONT)-full.owl: $(EDIT_PREPROCESSED) $(OTHER_SRC)
	$(ROBOT) merge --input $< \
		reason --reasoner ELK --equivalent-classes-allowed asserted-only \
		relax \
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

# Overwriting all obo files to remove excess labels, defs, comments.
$(ONT)-simple.obo: $(ONT)-simple.owl
	$(ROBOT) convert --input $< --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@.tmp.obo &&\
	cat $@.tmp.obo | grep -v ^owl-axioms > $@.tmp &&\
	cat $@.tmp | perl -0777 -e '$$_ = <>; s/(?:name[:].*\n)+name[:]/name:/g; print' | perl -0777 -e '$$_ = <>; s/(?:comment[:].*\n)+comment[:]/comment:/g; print' | perl -0777 -e '$$_ = <>; s/(?:def[:].*\n)+def[:]/def:/g; print' > $@
	rm -f $@.tmp.obo $@.tmp

# We want the OBO release to be based on the simple release. It needs to be annotated however in the way map releases (fbbt.owl) are annotated.
$(ONT).obo: $(ONT).owl
	$(ROBOT)  annotate --input $< --ontology-iri $(URIBASE)/$@ --version-iri $(ONTBASE)/releases/$(TODAY) \
	convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@.tmp.obo &&\
	cat $@.tmp.obo | grep -v ^owl-axioms > $@.tmp &&\
	cat $@.tmp | perl -0777 -e '$$_ = <>; s/(?:name[:].*\n)+name[:]/name:/g; print' | perl -0777 -e '$$_ = <>; s/(?:comment[:].*\n)+comment[:]/comment:/g; print' | perl -0777 -e '$$_ = <>; s/(?:def[:].*\n)+def[:]/def:/g; print' > $@
	rm -f $@.tmp.obo $@.tmp

$(ONT)-base.obo: $(ONT)-base.owl
	$(ROBOT) convert --input $< --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@.tmp.obo &&\
	cat $@.tmp.obo | grep -v ^owl-axioms > $@.tmp &&\
	cat $@.tmp | perl -0777 -e '$$_ = <>; s/(?:name[:].*\n)+name[:]/name:/g; print' | perl -0777 -e '$$_ = <>; s/(?:comment[:].*\n)+comment[:]/comment:/g; print' | perl -0777 -e '$$_ = <>; s/(?:def[:].*\n)+def[:]/def:/g; print' > $@
	rm -f $@.tmp.obo $@.tmp

$(ONT)-non-classified.obo: $(ONT)-non-classified.owl
	$(ROBOT) convert --input $< --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@.tmp.obo &&\
	cat $@.tmp.obo | grep -v ^owl-axioms > $@.tmp &&\
	cat $@.tmp | perl -0777 -e '$$_ = <>; s/(?:name[:].*\n)+name[:]/name:/g; print' | perl -0777 -e '$$_ = <>; s/(?:comment[:].*\n)+comment[:]/comment:/g; print' | perl -0777 -e '$$_ = <>; s/(?:def[:].*\n)+def[:]/def:/g; print' > $@
	rm -f $@.tmp.obo $@.tmp

$(ONT)-full.obo: $(ONT)-full.owl
	$(ROBOT) convert --input $< --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@.tmp.obo &&\
	cat $@.tmp.obo | grep -v ^owl-axioms > $@.tmp &&\
	cat $@.tmp | perl -0777 -e '$$_ = <>; s/(?:name[:].*\n)+name[:]/name:/g; print' | perl -0777 -e '$$_ = <>; s/(?:comment[:].*\n)+comment[:]/comment:/g; print' | perl -0777 -e '$$_ = <>; s/(?:def[:].*\n)+def[:]/def:/g; print' > $@
	rm -f $@.tmp.obo $@.tmp


flybase_controlled_vocabulary.obo:
	$(ROBOT) remove --input $(ONT)-simple.obo --term "http://purl.obolibrary.org/obo/FBcv_0008000" \
		convert -o $@.tmp.obo
	cat $@.tmp.obo | grep -v FlyBase_miscellaneous_CV | grep -v property_value: | sed '/^date[:]/c\date: $(OBODATE)' | sed '/^data-version[:]/c\data-version: $(DATE)' > $@
	rm -f $@.tmp.obo


#	owltools $(ONT)-simple --make-subset-by-properties part_of conditionality -o $@

######################################################
### Code for generating additional FlyBase reports ###
######################################################

FLYBASE_REPORTS = reports/obo_qc_fbcv.obo.txt reports/obo_qc_fbcv.owl.txt reports/obo_track_new_simple.txt reports/robot_simple_diff.txt reports/onto_metrics_calc.txt reports/chado_load_check_simple.txt

.PHONY: flybase_reports
flybase_reports: $(FLYBASE_REPORTS)

.PHONY: all_reports
all_reports: custom_reports robot_reports flybase_reports

.PHONY: release_reports
release_reports: robot_reports flybase_reports

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

export PERL5LIB := ${realpath ../scripts}
install_flybase_scripts:
	wget -O ../scripts/OboModel.pm $(obo_model)
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

reports/chado_load_check_simple.txt: install_flybase_scripts flybase_controlled_vocabulary.obo
	../scripts/chado_load_checks.pl flybase_controlled_vocabulary.obo > $@

reports/obo_qc_%.obo.txt: $*.obo
	$(ROBOT) merge -i $*.obo -i components/qc_assertions.owl convert -f obo --check false -o obo_qc_$*.obo &&\
	$(ROBOT) report -i obo_qc_$*.obo --profile qc-profile.txt --fail-on ERROR --print 5 -o $@
	rm -f obo_qc_$*.obo

reports/obo_qc_%.owl.txt: $*.owl
	$(ROBOT) merge -i $*.owl -i components/qc_assertions.owl -o obo_qc_$*.owl &&\
	$(ROBOT) report -i obo_qc_$*.owl --profile qc-profile.txt --fail-on None --print 5 -o $@
	rm -f obo_qc_$*.owl


#####################################################################################
### Regenerate placeholder definitions         (Pre-release) pipelines            ###
#####################################################################################
# There are two types of definitions that FBCV uses:
# "." (DOT-) definitions are those for which the formal definition is translated into a human readable definitions.
# "$sub_" (SUB-) definitions are those that have special placeholder string to substitute in definitions from external ontologies, mostly CHEBI

tmp/merged-source-pre.owl: $(SRC) components/dpo-simple.owl
	$(ROBOT) merge -i $(SRC) --output $@

tmp/auto_generated_definitions_seed_dot.txt: tmp/merged-source-pre.owl
	$(ROBOT) query --use-graphs false -f csv -i tmp/merged-source-pre.owl --query ../sparql/dot-definitions.sparql $@.tmp &&\
	cat $@.tmp | sort | uniq >  $@
	rm -f $@.tmp

tmp/auto_generated_definitions_seed_sub.txt: tmp/merged-source-pre.owl
	$(ROBOT) query --use-graphs false -f csv -i tmp/merged-source-pre.owl --query ../sparql/classes-with-placeholder-definitions.sparql $@.tmp &&\
	cat $@.tmp | sort | uniq >  $@
	rm -f $@.tmp

tmp/auto_generated_definitions_dot.owl: tmp/merged-source-pre.owl tmp/auto_generated_definitions_seed_dot.txt
	java -Xmx3G -jar ../scripts/eq-writer.jar $< tmp/auto_generated_definitions_seed_dot.txt flybase $@ NA add_dot_refs

tmp/auto_generated_definitions_sub.owl: tmp/merged-source-pre.owl tmp/auto_generated_definitions_seed_sub.txt
	java -Xmx3G -jar ../scripts/eq-writer.jar $< tmp/auto_generated_definitions_seed_sub.txt sub_external $@ NA source_xref

tmp/replaced_defs.txt:
	cat tmp/auto_generated_definitions_seed_sub.txt tmp/auto_generated_definitions_seed_dot.txt | sort | uniq > $@

$(EDIT_PREPROCESSED): $(SRC) tmp/auto_generated_definitions_sub.owl tmp/auto_generated_definitions_dot.owl
	cat $(SRC) | grep -v 'def[:] \"[.]\"' | grep -v 'sub_' > tmp/$(ONT)-edit-release.obo
	$(ROBOT) merge -i tmp/$(ONT)-edit-release.obo -i tmp/auto_generated_definitions_sub.owl -i tmp/auto_generated_definitions_dot.owl --collapse-import-closure false -o $(EDIT_PREPROCESSED)
