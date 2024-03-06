# Running the DPO release pipeline for TRAVIS
set -e

sh run.sh make MIR=false IMP=false prepare_release -B

