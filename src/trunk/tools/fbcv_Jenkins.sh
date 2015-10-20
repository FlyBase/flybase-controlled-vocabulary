#!/bin/sh 


echo $PATH 2>&1
# move GO update to here
# curl -L http://purl.obolibrary.org/obo/go.obo > go.obo #  commenting GO update for now. Unidentified problems 
echo 'PC_def_update.pl fbcv-edit.obo > tmp.obo' 2>&1
PC_def_update.pl fbcv/src/trunk/ontologies/fbcv-edit.obo > tmp.obo # Pull defs from named equivalent class to FBcv (from EC CHEBI terms)
echo 'update_EC_defs.pl tmp.obo | egrep -v "^equivalent_to: " > tmp2.obo' 2>&1
update_EC_defs.pl tmp.obo | egrep -v "^equivalent_to: " > tmp2.obo # Strip out assertions of equivalence between named classes after using these to generate autodefs.  In future I hope that improvements to owltools will eliminate the need for this grep -v.

# Merge down imports chain for lethal phase terms
echo 'owltools --use-catalog-xml ontologies/lethal_phase-edit.owl --merge-import-closure -o file://`pwd`/lethal_phase_imports_merged.owl' 2>&1
owltools --catalog-xml fbcv/src/trunk/ontologies/catalog-v001.xml fbcv/src/trunk/ontologies/lethal_phase-edit.owl --merge-import-closure -o file://`pwd`/lethal_phase_imports_merged.owl
echo 'owltools tmp2.obo --merge lethal_phase_imports_merged.owl --merge fbcv_auth_attrib_licence.owl --merge -o file://`pwd`/fbcv_merged.owl' 2>&1

owltools tmp2.obo --merge lethal_phase_imports_merged.owl --merge fbcv/src/trunk/ontologies/fbcv_auth_attrib_licence.owl -o file://`pwd`/fbcv_merged.owl
# removed GO update from following oort run - version downloaded at Apr 30, 2013 2:43:22  caused build fail.  Some problem with has_part stanza. See console out.
echo 'ontology-release-runner --reasoner hermit fbcv_merged.owl  --simple --asserted --allow-overwrite --no-subsets --outdir oort' 2>&1
ontology-release-runner --reasoner hermit fbcv_merged.owl  --simple --relaxed --asserted --allow-overwrite --no-subsets --outdir oort  # Note - generating subsets cause release fail.
# Cleaning up
rm tmp.obo
rm tmp2.obo
rm lethal_phase_imports_merged.owl
rm fbcv_merged.owl
 


