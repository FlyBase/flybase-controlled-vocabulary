## Customize Makefile settings for fbcv
##
## If you need to customize your Makefile, make
## changes here rather than in the main Makefile

######################################################
### Download and integrate the DPO component       ###
######################################################

DPO=http://purl.obolibrary.org/obo/dpo/dpo-simple.owl

components/dpo-simple.owl: .FORCE
	wget $(DPO) && mv dpo-simple.owl tmp/dpo-simple.owl
	$(ROBOT) annotate -i tmp/dpo-simple.owl --ontology-iri $(ONTBASE)/$@ --version-iri $(ONTBASE)/releases/$(TODAY)/$@ -o $@
	rm tmp/dpo-simple.owl


###################################################
### Custom pipeline to generate fbcv-simple.owl ###
###################################################

tmp/fbcv_terms.txt: $(SRC)
	$(ROBOT) query --use-graphs true -f csv -i $(SRC) --query ../sparql/fbcv_terms.sparql $@

tmp/$(ONT)-stripped.owl: $(ONT).owl tmp/fbcv_terms.txt
	$(ROBOT) filter --input $< --term-file tmp/fbcv_terms.txt --trim false \
		convert -o $@

# fbcv_signature.txt should contain all FBCV terms and all properties (and subsets) used by the ontology.
# It serves like a proper signature, but including annotation properties
tmp/fbcv_signature.txt: tmp/$(ONT)-stripped.owl tmp/fbcv_terms.txt
	$(ROBOT) query -f csv -i $< --query ../sparql/object-properties.sparql $@_prop.tmp &&\
	cat tmp/fbcv_terms.txt $@_prop.tmp | grep -i fbcv |sort | uniq > $@ &&\
	rm $@_prop.tmp

# We generate the -simple artifact almost exactly as the ODK would do,
# the main difference being an extra step where we remove all terms
# outside of the FBcv signature as generated above.
$(ONT)-simple.owl: $(ONT).owl tmp/fbcv_signature.txt
	$(ROBOT) reason --input $< --reasoner ELK --equivalent-classes-allowed asserted-only \
		relax \
		remove --axioms equivalent \
		relax \
		filter --term-file $(SIMPLESEED) --select "annotations ontology anonymous self" \
		  --trim true --signature true \
		remove --term-file tmp/fbcv_signature.txt --select complement --trim false \
		reduce -r ELK \
		annotate --ontology-iri $(ONTBASE)/$@ --version-iri $(ONTBASE)/releases/$(TODAY)/$@ \
		  --annotation oboInOwl:date "$(OBODATE)" --output $@.tmp.owl && mv $@.tmp.owl $@


##############################################
### Custom rules to generate OBO artifacts ###
##############################################

# We want the OBO release to be based on the simple release. It needs to be annotated however in the way map releases (fbbt.owl) are annotated.
$(ONT).obo: $(ONT)-simple.owl
	$(ROBOT) annotate --input $< \
		          --ontology-iri $(URIBASE)/$@ \
		          --version-iri $(ONTBASE)/releases/$(TODAY) \
		 convert --check false -f obo $(OBO_FORMAT_OPTIONS) -o $@

flybase_additions.obo: $(ONT)-simple.obo
	python3 $(SCRIPTSDIR)/FB_typedefs.py

flybase_controlled_vocabulary.obo: $(ONT)-simple.obo flybase_additions.obo
	$(ROBOT) merge --input $(ONT)-simple.obo --input flybase_additions.obo --collapse-import-closure false \
		remove --term "http://purl.obolibrary.org/obo/FBcv_0008000" \
		convert -o $@.tmp.obo
	cat $@.tmp.obo | sed '/./{H;$!d;} ; x ; s/\(\[Typedef\]\nid:[ ]\)\([[:alpha:]_]*\n\)\(name:[ ]\)\([[:alpha:][:punct:] ]*\n\)/\1\2\3\2/' | grep -v FlyBase_miscellaneous_CV | grep -v property_value: | sed '/^date[:]/c\date: $(OBODATE)' | sed '/^data-version[:]/c\data-version: $(TODAY)' | sed 1d > $@
	rm -f $@.tmp.obo

# Make sure the flybase version is included in $(ASSETS)
# and generated as needed
MAIN_FILES += flybase_controlled_vocabulary.obo
all_assets: flybase_controlled_vocabulary.obo


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

$(EDIT_PREPROCESSED): $(SRC) all_robot_plugins
	$(ROBOT) flybase:rewrite-def -i $< --dot-definitions --sub-definitions --filter-prefix FBcv -o $@
