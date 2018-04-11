#!/bin/sh 


echo $PATH 2>&1
# move GO update to here
# curl -L http://purl.obolibrary.org/obo/go.obo > go.obo #  commenting GO update for now. Unidentified problems 
echo 'PC_def_update.pl fbcv-edit.obo > tmp.obo' 2>&1
PC_def_update.pl src/trunk/ontologies/dpo-edit.obo > tmp.obo # Pull defs from named equivalent class to FBcv (from EC CHEBI terms)

# Merge down imports chain for lethal phase terms
echo 'owltools --use-catalog-xml ontologies/lethal_phase-edit.owl --merge-import-closure -o file://`pwd`/lethal_phase_imports_merged.owl' 2>&1
owltools --catalog-xml src/trunk/ontologies/catalog-v001.xml src/trunk/ontologies/lethal_phase-edit.owl --merge-import-closure -o file://`pwd`/lethal_phase_imports_merged.owl
echo 'owltools tmp2.obo --merge lethal_phase_imports_merged.owl --merge fbcv_auth_attrib_licence.owl --merge -o file://`pwd`/fbcv_merged.owl' 2>&1

owltools tmp.obo --merge lethal_phase_imports_merged.owl --merge src/trunk/ontologies/fbcv_auth_attrib_licence.owl -o file://`pwd`/dpo_merged.owl
# removed GO update from following oort run - version downloaded at Apr 30, 2013 2:43:22  caused build fail.  Some problem with has_part stanza. See console out.
echo 'ontology-release-runner --reasoner hermit fbcv_merged.owl  --simple --asserted --allow-overwrite --no-subsets --outdir oort' 2>&1
ontology-release-runner --reasoner hermit dpo_merged.owl --prefix fbcv  --simple --relaxed --asserted --allow-overwrite --no-subsets --outdir oort  # Note - generating subsets cause release fail.
# Cleaning up
rm tmp.obo
rm lethal_phase_imports_merged.owl
rm dpo_merged.owl
 


